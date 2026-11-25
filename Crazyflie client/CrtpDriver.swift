//
//  CrtpDriver.swift
//  Crazyflie client
//
//  Created by fanbaoying on 2020/4/29.
//  Copyright © 2020 Bitcraze. All rights reserved.
//

import UIKit

protocol CrtpDriver: class {
    var connectionError: String? { get }
    func connect(_ address: String?, callback: @escaping (Bool) -> ())
    func disconnect()
    func sendPacket(_ packet: Data, callback: ((Bool) -> ())?)
    func onStateUpdated(_ callback: @escaping (NSString) -> ())
}
