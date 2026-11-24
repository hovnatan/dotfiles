#!/usr/bin/swift
// Night Shift from the command line, for home/.hammerspoon/mpv_night_shift.lua:
//
//   night_shift.swift status   enabled=no mode=sun scheduled=yes
//   night_shift.swift off      turn it off if it is on
//   night_shift.swift resume   turn it on if its schedule has it on now
//
// Each prints one line saying what it found or did. `scheduled` is whether
// the schedule in System Settings > Displays > Night Shift covers this
// minute: sunset to sunrise, or the custom hours. With no schedule nothing
// says when it should be on, so `resume` leaves it off.
//
// macOS has no public API or command for Night Shift. This talks to
// corebrightnessd through CoreBrightness, the private framework System
// Settings uses, so a macOS release can break it: every call it relies on
// is checked and a missing one exits 1 naming it. Checked on macOS 27.2.

import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("night_shift: \(message)\n".utf8))
  exit(1)
}

// What -[CBBlueLightClient getBlueLightStatus:] fills in. The framework ships
// no header: the fields are as Shifty and nightlight declare them.
struct Status {
  var active = false
  var enabled = false
  var sunSchedulePermitted = false
  var mode: Int32 = 0
  var fromHour: Int32 = 0
  var fromMinute: Int32 = 0
  var toHour: Int32 = 0
  var toMinute: Int32 = 0
  var disableFlags: UInt64 = 0
  var available = false
}

enum Mode: Int32 {
  case off = 0
  case sun = 1
  case custom = 2

  var name: String {
    switch self {
    case .off: return "off"
    case .sun: return "sun"
    case .custom: return "custom"
    }
  }
}

let framework = "/System/Library/PrivateFrameworks/CoreBrightness.framework"
guard let bundle = Bundle(path: framework), bundle.load() else {
  fail("cannot load \(framework)")
}

func instance(of name: String) -> NSObject {
  guard let type = NSClassFromString(name) as? NSObject.Type else {
    fail("CoreBrightness has no class \(name)")
  }
  return type.init()
}

func method<T>(_ object: NSObject, _ name: String, as _: T.Type) -> (T, Selector) {
  let selector = NSSelectorFromString(name)
  guard object.responds(to: selector) else {
    fail("\(type(of: object)) has no method \(name)")
  }
  return (unsafeBitCast(object.method(for: selector), to: T.self), selector)
}

let client = instance(of: "CBBlueLightClient")

func status() -> Status {
  typealias Get = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
  let (get, selector) = method(client, "getBlueLightStatus:", as: Get.self)
  // allocate() gives the stride, 40 bytes, which is the C struct's size; a
  // Swift variable is 33 and the call would write past it.
  let buffer = UnsafeMutablePointer<Status>.allocate(capacity: 1)
  defer { buffer.deallocate() }
  buffer.initialize(to: Status())
  guard get(client, selector, UnsafeMutableRawPointer(buffer)) else {
    fail("getBlueLightStatus: returned false")
  }
  return buffer.pointee
}

func setEnabled(_ on: Bool) {
  typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Bool
  let (set, selector) = method(client, "setEnabled:", as: Set.self)
  guard set(client, selector, on) else {
    fail("setEnabled:\(on) returned false")
  }
  guard status().enabled == on else {
    fail("setEnabled:\(on) returned true, but Night Shift is still \(on ? "off" : "on")")
  }
}

func mode(_ status: Status) -> Mode {
  guard let mode = Mode(rawValue: status.mode) else {
    fail("unknown schedule mode \(status.mode): 0 off, 1 sun and 2 custom are the ones known")
  }
  return mode
}

// Whether a custom schedule from..<to, in minutes of the day, covers `now`.
// 22:00 to 7:00 runs past midnight.
func covers(from: Int, to: Int, now: Int) -> Bool {
  from <= to ? (from <= now && now < to) : (now >= from || now < to)
}

func isDaylight() -> Bool {
  let system = instance(of: "BrightnessSystemClient")
  let copy = NSSelectorFromString("copyPropertyForKey:")
  guard system.responds(to: copy) else {
    fail("BrightnessSystemClient has no method copyPropertyForKey:")
  }
  let key = "BlueLightSunSchedule"
  guard let schedule = system.perform(copy, with: key)?.takeRetainedValue() as? [String: Any] else {
    fail("BrightnessSystemClient has no \(key): is Location Services off for System Customization?")
  }
  guard let daylight = schedule["isDaylight"] as? Bool else {
    fail("\(key) has no isDaylight: \(schedule)")
  }
  return daylight
}

// The reason comes with the answer, for the line `resume` prints.
func scheduled(_ status: Status) -> (on: Bool, why: String) {
  switch mode(status) {
  case .off:
    return (false, "no schedule")
  case .sun:
    let daylight = isDaylight()
    return (!daylight, "sunset to sunrise, and it is \(daylight ? "day" : "night")")
  case .custom:
    let time = Calendar.current.dateComponents([.hour, .minute], from: Date())
    let on = covers(
      from: Int(status.fromHour) * 60 + Int(status.fromMinute),
      to: Int(status.toHour) * 60 + Int(status.toMinute),
      now: time.hour! * 60 + time.minute!)
    let hours = String(
      format: "%d:%02d to %d:%02d", status.fromHour, status.fromMinute, status.toHour,
      status.toMinute)
    return (on, "\(hours), and it is \(on ? "inside" : "outside") that")
  }
}

let usage = "usage: night_shift.swift status|off|resume"
guard CommandLine.arguments.count == 2 else {
  fail(usage)
}
let now = status()
// A Mac whose display cannot do Night Shift has nothing to switch.
guard now.available else {
  print("Night Shift is not available on this Mac: nothing done")
  exit(0)
}

func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

switch CommandLine.arguments[1] {
case "status":
  print(
    "enabled=\(yesNo(now.enabled)) mode=\(mode(now).name) scheduled=\(yesNo(scheduled(now).on))")
case "off":
  if now.enabled {
    setEnabled(false)
    print("was on: turned off")
  } else {
    print("already off")
  }
case "resume":
  let (on, why) = scheduled(now)
  if now.enabled {
    print("already on")
  } else if on {
    setEnabled(true)
    print("turned on (\(why))")
  } else {
    print("left off (\(why))")
  }
default:
  fail(usage)
}
