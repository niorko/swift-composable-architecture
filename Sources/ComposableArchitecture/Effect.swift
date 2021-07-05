import Combine
import Foundation
import PromiseKit

/// The ``Effect`` type encapsulates a unit of work that can be run in the outside world, and can
/// feed data back to the ``Store``. It is the perfect place to do side effects, such as network
/// requests, saving/loading from disk, creating timers, interacting with dependencies, and more.
///
/// Effects are returned from reducers so that the ``Store`` can perform the effects after the
/// reducer is done running. It is important to note that ``Store`` is not thread safe, and so all
/// effects must receive values on the same thread, **and** if the store is being used to drive UI
/// then it must receive values on the main thread.
///
/// An effect simply wraps a `Publisher` value and provides some convenience initializers for
/// constructing some common types of effects.
public struct Effect<Output> {
  
  private let promises: [CancellablePromise<Output>]

  private init(_ promises: [CancellablePromise<Output>]) {
    self.promises = promises
  }
  
  private init(resolver: (Resolver<Output>) throws -> Void) {
    self.promises = [CancellablePromise<Output>(resolver: resolver)]
  }
  
  /// Initializes an effect that wraps a publisher. Each emission of the wrapped publisher will be
  /// emitted by the effect.
  ///
  /// This initializer is useful for turning any publisher into an effect. For example:
  ///
  /// ```swift
  /// Effect(
  ///   NotificationCenter.default
  ///     .publisher(for: UIApplication.userDidTakeScreenshotNotification)
  /// )
  /// ```
  ///
  /// Alternatively, you can use the `.eraseToEffect()` method that is defined on the `Publisher`
  /// protocol:
  ///
  /// ```swift
  /// NotificationCenter.default
  ///   .publisher(for: UIApplication.userDidTakeScreenshotNotification)
  ///   .eraseToEffect()
  /// ```
  ///
  /// - Parameter publisher: A publisher.
  public init<T: Thenable>(_ thenable: T) where T.T == Output {
    self.promises = [CancellablePromise(thenable)]
  }

  /// Initializes an effect that immediately emits the value passed in.
  ///
  /// - Parameter value: The value that is immediately emitted by the effect.
  public init(value: Output) {
    self.promises = [CancellablePromise<Output>(Promise.value(value))]
  }

  /// Initializes an effect that immediately fails with the error passed in.
  ///
  /// - Parameter error: The error that is immediately emitted by the effect.
  public init(error: Error) {
    self.promises = [CancellablePromise(error: error)]
  }

  /// An effect that does nothing and completes immediately. Useful for situations where you must
  /// return an effect, but you don't need to do anything.
  public static var none: Effect {
    Effect([])
  }

  /// Initializes an effect that lazily executes some work in the real world and synchronously sends
  /// that data back into the store.
  ///
  /// For example, to load a user from some JSON on the disk, one can wrap that work in an effect:
  ///
  /// ```swift
  /// Effect<User, Error>.result {
  ///   let fileUrl = URL(
  ///     fileURLWithPath: NSSearchPathForDirectoriesInDomains(
  ///       .documentDirectory, .userDomainMask, true
  ///     )[0]
  ///   )
  ///   .appendingPathComponent("user.json")
  ///
  ///   let result = Result<User, Error> {
  ///     let data = try Data(contentsOf: fileUrl)
  ///     return try JSONDecoder().decode(User.self, from: $0)
  ///   }
  ///
  ///   return result
  /// }
  /// ```
  ///
  /// - Parameter attemptToFulfill: A closure encapsulating some work to execute in the real world.
  /// - Returns: An effect.
  public static func result(_ attemptToFulfill: @escaping () -> Swift.Result<Output, Error>) -> Self {
    Self { resolver in
      let result = attemptToFulfill()
      do {
        let value = try result.get()
        resolver.fulfill(value)
      } catch {
        resolver.reject(error)
      }
    }
  }

  /// Concatenates a variadic list of effects together into a single effect, which runs the effects
  /// one after the other.
  ///
  /// - Warning: Combine's `Publishers.Concatenate` operator, which this function uses, can leak
  ///   when its suffix is a `Publishers.MergeMany` operator, which is used throughout the
  ///   Composable Architecture in functions like ``Reducer/combine(_:)-1ern2``.
  ///
  ///   Feedback filed: <https://gist.github.com/mbrandonw/611c8352e1bd1c22461bd505e320ab58>
  ///
  /// - Parameter effects: A variadic list of effects.
  /// - Returns: A new effect
  public static func concatenate(_ effects: Effect...) -> Effect {
    .concatenate(effects)
  }

  /// Concatenates a collection of effects together into a single effect, which runs the effects one
  /// after the other.
  ///
  /// - Warning: Combine's `Publishers.Concatenate` operator, which this function uses, can leak
  ///   when its suffix is a `Publishers.MergeMany` operator, which is used throughout the
  ///   Composable Architecture in functions like ``Reducer/combine(_:)-1ern2``.
  ///
  ///   Feedback filed: <https://gist.github.com/mbrandonw/611c8352e1bd1c22461bd505e320ab58>
  ///
  /// - Parameter effects: A collection of effects.
  /// - Returns: A new effect
  public static func concatenate<C: Collection>(
    _ effects: C
  ) -> Effect where C.Element == Effect {
    let allPromises = effects.flatMap(\.promises)
    return Effect(allPromises)
  }

  /// Merges a variadic list of effects together into a single effect, which runs the effects at the
  /// same time.
  ///
  /// - Parameter effects: A list of effects.
  /// - Returns: A new effect
  public static func merge(
    _ effects: Effect...
  ) -> Effect {
    .merge(effects)
  }

  /// Merges a sequence of effects together into a single effect, which runs the effects at the same
  /// time.
  ///
  /// - Parameter effects: A sequence of effects.
  /// - Returns: A new effect
  public static func merge<S: Sequence>(_ effects: S) -> Effect where S.Element == Effect {
    Effect(effects.flatMap(\.promises))
  }

  /// Creates an effect that executes some work in the real world that doesn't need to feed data
  /// back into the store.
  ///
  /// - Parameter work: A closure encapsulating some work to execute in the real world.
  /// - Returns: An effect.
  public static func fireAndForget(_ work: @escaping () -> Void) -> Effect {
    Effect<Void>
      .catching(work)
      .flatMap { _ in .none }
  }

  /// Transforms all elements from the upstream effect with a provided closure.
  ///
  /// - Parameter transform: A closure that transforms the upstream effect's output to a new output.
  /// - Returns: A publisher that uses the provided closure to map elements from the upstream effect
  ///   to new elements that it then publishes.
  public func map<U>(_ transform: @escaping (Output) -> U) -> Effect<U> {
    let newPromises = promises.map { $0.map(transform) }
    return Effect<U>.init(newPromises)
  }
  
  public func flatMap<U>(_ transform: @escaping (Output) -> Effect<U>) -> Effect<U> {
    let newPromises: [CancellablePromise<U>] = promises.map { promise -> CancellablePromise<U> in
      return promise.then { output -> CancellablePromise<U> in
        let newEffect: Effect<U> = transform(output)
        return newEffect.promises.first!
      }
    }
    return Effect<U>(newPromises)
  }

  /// Initializes an effect that lazily executes some work in the real world and synchronously sends
  /// that data back into the store.
  ///
  /// For example, to load a user from some JSON on the disk, one can wrap that work in an effect:
  ///
  /// ```swift
  /// Effect<User, Error>.catching {
  ///   let fileUrl = URL(
  ///     fileURLWithPath: NSSearchPathForDirectoriesInDomains(
  ///       .documentDirectory, .userDomainMask, true
  ///     )[0]
  ///   )
  ///   .appendingPathComponent("user.json")
  ///
  ///   let data = try Data(contentsOf: fileUrl)
  ///   return try JSONDecoder().decode(User.self, from: $0)
  /// }
  /// ```
  ///
  /// - Parameter work: A closure encapsulating some work to execute in the real world.
  /// - Returns: An effect.
  public static func catching(_ work: @escaping () throws -> Output) -> Self {
    Self.init { resolver in
      do {
        let value = try work()
        resolver.fulfill(value)
      } catch {
        resolver.reject(error)
      }
    }
  }
}

extension Thenable {
  /// DOC
  public func eraseToEffect() -> Effect<T> {
    Effect<T>(self)
  }
}
