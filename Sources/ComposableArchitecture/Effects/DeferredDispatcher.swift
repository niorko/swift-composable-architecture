import Foundation
import Dispatch
import PromiseKit

public protocol DeferredDispatcher: Dispatcher {
  func dispatchAfter(deadline: DispatchTime, body: @escaping () -> Void)
}

// Avoid having to hard-code any particular defaults for qos or flags
internal extension DispatchQueue {
    final func asyncD(group: DispatchGroup? = nil, qos: DispatchQoS? = nil, flags: DispatchWorkItemFlags? = nil, execute body: @escaping () -> Void) {
        switch (qos, flags) {
        case (nil, nil):
            async(group: group, execute: body)
        case (nil, let flags?):
            async(group: group, flags: flags, execute: body)
        case (let qos?, nil):
            async(group: group, qos: qos, execute: body)
        case (let qos?, let flags?):
            async(group: group, qos: qos, flags: flags, execute: body)
        }
    }
  
  final func asyncAfterD(deadline: DispatchTime, group: DispatchGroup? = nil, qos: DispatchQoS? = nil, flags: DispatchWorkItemFlags? = nil, execute body: @escaping () -> Void) {
      switch (qos, flags) {
      case (let qos?, let flags?):
        asyncAfter(deadline: deadline, qos: qos, flags: flags, execute: body)
      default:
        asyncAfter(deadline: deadline, execute: body)
      }
  }
}

extension CurrentThreadDispatcher: DeferredDispatcher {
  public func dispatchAfter(deadline: DispatchTime, body: @escaping () -> Void) {
    body()
  }
}

extension DispatchQueue: DeferredDispatcher {
  public func dispatchAfter(deadline: DispatchTime, body: @escaping () -> Void) {
    asyncAfter(deadline: deadline, execute: body)
  }
}

public struct DeferredDispatchQueueDispatcher: DeferredDispatcher {
    
  let queue: DispatchQueue
  let group: DispatchGroup?
  let qos: DispatchQoS?
  let flags: DispatchWorkItemFlags?
  
  public init(queue: DispatchQueue, group: DispatchGroup? = nil, qos: DispatchQoS? = nil, flags: DispatchWorkItemFlags? = nil) {
    self.queue = queue
    self.group = group
    self.qos = qos
    self.flags = flags
  }
  
  public func dispatch(_ body: @escaping () -> Void) {
    queue.asyncD(group: group, qos: qos, flags: flags, execute: body)
  }
  
  public func dispatchAfter(deadline: DispatchTime, body: @escaping () -> Void) {
    queue.asyncAfterD(deadline: deadline, group: group, qos: qos, flags: flags, execute: body)
  }
}
