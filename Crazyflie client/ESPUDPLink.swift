//
//  ESPUDPLink.swift
//  Crazyflie client
//
//  Created by fanbaoying on 2020/4/29.
//  Copyright © 2020 Bitcraze. All rights reserved.
//

import Foundation
import CocoaAsyncSocket

class ESPUDPLink: NSObject, CrtpDriver, GCDAsyncUdpSocketDelegate {
    private let appPort: UInt16 = 2399
    private let devicePort: UInt16 = 2390
    private let udpHost = "192.168.43.42"
    private let echoHeader: UInt8 = 0xF0 // CRTP link port 15, channel 0
    private var clientSocket: GCDAsyncUdpSocket!
    private var receiving = false
    private var retryTimer: Timer?
    private var timeoutTimer: Timer?
    private var echoPayload: Data?
    private var connectCallback: ((Bool) -> ())?
    private var stateCallback: ((NSString) -> ())?
    private(set) var connectionError: String?
    private var state = "idle" {
        didSet { stateCallback?(state as NSString) }
    }

    override init() {
        super.init()
        clientSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
    }

    func connect(_ address: String?, callback: @escaping (Bool) -> ()) {
        guard state == "idle", connectCallback == nil else {
            callback(false)
            return
        }

        connectionError = nil
        connectCallback = callback
        state = "connecting"
        do {
            if !receiving {
                try clientSocket.bind(toPort: appPort)
                try clientSocket.beginReceiving()
                receiving = true
            }
        } catch {
            clientSocket.close()
            finishConnection(false, error: "Could not open UDP port \(appPort): \(error.localizedDescription)")
            return
        }

        // A fresh challenge distinguishes this attempt from an old reply.
        echoPayload = Data((0..<4).map { _ in UInt8.random(in: 0...255) })
        sendEcho()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.sendEcho()
        }
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.finishConnection(false, error: "No reply from ESP Drone at 192.168.43.42:2390. Join its ESP-DRONE Wi-Fi and allow Local Network access in Settings.")
        }
    }

    private func sendEcho() {
        guard let payload = echoPayload else { return }
        var packet = Data([echoHeader])
        packet.append(payload)
        packet.append(UInt8(packet.reduce(0) { ($0 + Int($1)) & 0xff }))
        clientSocket.send(packet, toHost: udpHost, port: devicePort, withTimeout: 1, tag: 1)
    }

    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        guard let payload = echoPayload, data.count == payload.count + 2 else { return }
        let bytes = [UInt8](data)
        let checksum = UInt8(bytes.dropLast().reduce(0) { ($0 + Int($1)) & 0xff })
        guard checksum == bytes[bytes.count - 1],
              (bytes[0] & 0xF3) == echoHeader,
              Data(bytes[1..<(bytes.count - 1)]) == payload,
              GCDAsyncUdpSocket.host(fromAddress: address) == udpHost,
              GCDAsyncUdpSocket.port(fromAddress: address) == devicePort else { return }
        finishConnection(true, error: nil)
    }

    func udpSocket(_ sock: GCDAsyncUdpSocket, didNotSendDataWithTag tag: Int, dueToError error: Error?) {
        if tag == 1 {
            finishConnection(false, error: "Could not send to ESP Drone: \(error?.localizedDescription ?? "UDP error")")
        }
    }

    func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error?) {
        receiving = false
        if connectCallback != nil {
            finishConnection(false, error: "UDP socket closed: \(error?.localizedDescription ?? "unknown error")")
        } else if state == "connected" {
            connectionError = "Connection to ESP Drone closed."
            state = "idle"
        }
    }

    private func finishConnection(_ connected: Bool, error: String?) {
        guard let callback = connectCallback else { return }
        retryTimer?.invalidate()
        timeoutTimer?.invalidate()
        retryTimer = nil
        timeoutTimer = nil
        echoPayload = nil
        connectCallback = nil
        connectionError = error
        state = connected ? "connected" : "idle"
        callback(connected)
    }

    func disconnect() {
        retryTimer?.invalidate()
        timeoutTimer?.invalidate()
        retryTimer = nil
        timeoutTimer = nil
        echoPayload = nil
        connectCallback = nil
        if state != "idle" { state = "idle" }
    }

    func sendPacket(_ packet: Data, callback: ((Bool) -> ())?) {
        guard state == "connected" else {
            callback?(false)
            return
        }
        clientSocket.send(packet, toHost: udpHost, port: devicePort, withTimeout: 1, tag: 0)
        callback?(true)
    }

    func onStateUpdated(_ callback: @escaping (NSString) -> ()) {
        stateCallback = callback
    }
}
