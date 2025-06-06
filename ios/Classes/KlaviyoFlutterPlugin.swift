import UIKit
import Flutter
import KlaviyoSwift

/// A class that receives and handles calls from Flutter to complete the payment.
public class KlaviyoFlutterPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate { //, FlutterApplicationLifeCycleDelegate {
  private static let methodChannelName = "com.rightbite.denisr/klaviyo"
  private static let firebaseMessagingMethodChannelName = "plugins.flutter.io/firebase_messaging"
  private static let flutterLocalNotificationsMethodChannelName = "dexterous.com/flutter/local_notifications"
    
  private let METHOD_UPDATE_PROFILE = "updateProfile"
  private let METHOD_INITIALIZE = "initialize"
  private let METHOD_SEND_TOKEN = "sendTokenToKlaviyo"
  private let METHOD_LOG_EVENT = "logEvent"
  private let METHOD_HANDLE_PUSH = "handlePush"
  private let METHOD_GET_EXTERNAL_ID = "getExternalId"
  private let METHOD_RESET_PROFILE = "resetProfile"
  private let GET_NOTIFICATION_APP_LAUNCH_DETAILS_METHOD = "getNotificationAppLaunchDetails"

  private let METHOD_SET_EMAIL = "setEmail"
  private let METHOD_GET_EMAIL = "getEmail"
  private let METHOD_SET_PHONE_NUMBER = "setPhoneNumber"
  private let METHOD_GET_PHONE_NUMBER = "getPhoneNumber"

  private var _channel:FlutterMethodChannel!
  private var _receivedNotification:[String: Any] = [:]
  private var _isAppInitialized = false
  private var _isAppLaunchedFromNotification = false

  private let klaviyo = KlaviyoSDK()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    let flutterLocalNotificationsChannel = FlutterMethodChannel(name: flutterLocalNotificationsMethodChannelName, binaryMessenger: messenger)

    let instance = KlaviyoFlutterPlugin()
    instance._channel = FlutterMethodChannel(name: firebaseMessagingMethodChannelName, binaryMessenger: messenger)

    registrar.addMethodCallDelegate(instance, channel: channel)
    // registrar.addMethodCallDelegate(instance, channel: flutterLocalNotificationsChannel)
    registrar.addApplicationDelegate(instance)
  }

  // below method will be called when the user interacts with the push notification
  public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    // Log the notification response with a tag
    NSLog("KlaviyoFlutterPlugin: userNotificationCenter: didReceive: \(response.notification.request.content.body)")
    // decrement the badge count on the app icon
    if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(UIApplication.shared.applicationIconBadgeNumber - 1)
    } else {
        UIApplication.shared.applicationIconBadgeNumber -= 1
    }

    let remoteNotification = response.notification.request.content.userInfo
    // Log remoteNotification with tag
    NSLog("KlaviyoFlutterPlugin: userNotificationCenter: didReceive: remoteNotification: \(remoteNotification)")
    if let body = remoteNotification["body"] as? [String: Any],
     body["_k"] != nil {
      let notificationDict = self.remoteMessageUserInfoToDict(remoteNotification)
      // Log notificationDict with tag
      NSLog("KlaviyoFlutterPlugin: userNotificationCenter: didReceive: notificationDict: \(notificationDict)")
      if (!_isAppInitialized) {
        _receivedNotification = notificationDict
        _isAppLaunchedFromNotification = true
      } else {
        self._channel.invokeMethod("Messaging#onMessageOpenedApp", arguments: notificationDict)
      }
      completionHandler()
      return
    }

    // If this notification is Klaviyo's notification we'll handle it
    // else pass it on to the next push notification service to which it may belong
    let handled = KlaviyoSDK().handle(notificationResponse: response, withCompletionHandler: completionHandler)
    if !handled {
        completionHandler()
    }
  }

  // below method is called when the app receives push notifications when the app is the foreground
  public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                  willPresent notification: UNNotification,
                                  withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    // Log the notification data with a tag
    NSLog("KlaviyoFlutterPlugin: userNotificationCenter: willPresent: \(notification.request.content.body)")
    let remoteNotification = notification.request.content.userInfo
    // Log remoteNotification with tag
    NSLog("KlaviyoFlutterPlugin: userNotificationCenter: willPresent: remoteNotification: \(remoteNotification)")
    if let body = remoteNotification["body"] as? [String: Any],
     body["_k"] != nil {
      let notificationDict = self.remoteMessageUserInfoToDict(remoteNotification)
      // Log notificationDict with tag
      NSLog("KlaviyoFlutterPlugin: userNotificationCenter: willPresent: notificationDict: \(notificationDict)")
      _channel.invokeMethod("Messaging#onMessage", arguments: notificationDict)
      completionHandler([])
      return
    }
    var options: UNNotificationPresentationOptions =  [.alert]
    if #available(iOS 14.0, *) {
      options = [.list, .banner]
    }
    completionHandler(options)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
        case METHOD_INITIALIZE:
          let arguments = call.arguments as! [String: Any]
          klaviyo.initialize(with: arguments["apiKey"] as! String)
          self._isAppInitialized = true
          if (self._isAppLaunchedFromNotification) {
            NSLog("KlaviyoFlutterPlugin: Initializing Klaviyo from notification")
            self._channel.invokeMethod("Messaging#onMessageOpenedApp", arguments: self._receivedNotification)
          }
          result("Klaviyo initialized")

        case METHOD_SEND_TOKEN:
          let arguments = call.arguments as! [String: Any]
          let tokenData = arguments["token"] as! String
          klaviyo.set(pushToken: Data(hexString: tokenData))
          result("Token sent to Klaviyo")

        case METHOD_UPDATE_PROFILE:
          let arguments = call.arguments as! [String: Any]
          // parsing location
          let address1 = arguments["address1"] as? String
          let address2 = arguments["address2"] as? String
          let latitude = (arguments["latitude"] as? String)?.toDouble
          let longitude = (arguments["longitude"] as? String)?.toDouble
          let region = arguments["region"] as? String
        
          var location: Profile.Location?
        
          if(address1 != nil && address2 != nil && latitude != nil && longitude != nil && region != nil) {
            location = Profile.Location(
                address1: address1,
                address2: address2,
                latitude: latitude,
                longitude: longitude,
                region: region)
          }
        
        
          let profile = Profile(
            email: arguments["email"] as? String,
            phoneNumber: arguments["phone_number"] as? String,
            externalId: arguments["external_id"] as? String,
            firstName: arguments["first_name"] as? String,
            lastName: arguments["last_name"] as? String,
            organization: arguments["organization"] as? String,
            title: arguments["title"] as? String,
            image: arguments["image"] as? String,
            location: location,
            properties: arguments["properties"] as? [String:Any]
            )
          klaviyo.set(profile: profile)
          result("Profile updated")

        case METHOD_LOG_EVENT:
          let arguments = call.arguments as! [String: Any]
          let event = Event(
            name: .customEvent(arguments["name"] as! String),
            properties: arguments["metaData"] as? [String: Any])

          klaviyo.create(event: event)
          result("Event: [\(event)] created")
        
        case METHOD_HANDLE_PUSH:
          let arguments = call.arguments as! [String: Any]

          if let properties = arguments["message"] as? [String: Any],
            let _ = properties["_k"] {
              klaviyo.create(event: Event(name: .customEvent("$opened_push"), properties: properties))

              return result(true)
          }
          result(false)

        case METHOD_GET_EXTERNAL_ID:
          result(klaviyo.externalId)

        case METHOD_RESET_PROFILE:
          klaviyo.resetProfile()
          result(true)

        case METHOD_GET_EMAIL:
          result(klaviyo.email)

        case METHOD_GET_PHONE_NUMBER:
          result(klaviyo.phoneNumber)

        case METHOD_SET_EMAIL:
          let arguments = call.arguments as! [String: Any]
          klaviyo.set(email: arguments["email"] as! String)
          result("Email updated")

        case METHOD_SET_PHONE_NUMBER:
          let arguments = call.arguments as! [String: Any]
          klaviyo.set(phoneNumber: arguments["phoneNumber"] as! String)
          result("Phone updated")

        case GET_NOTIFICATION_APP_LAUNCH_DETAILS_METHOD:
          var notificationAppLaunchDetails: [String: Any] = [:]
          notificationAppLaunchDetails["notificationLaunchedApp"] = self._isAppLaunchedFromNotification
          notificationAppLaunchDetails["notificationResponse"] = self._receivedNotification
          NSLog("KlaviyoFlutterPlugin: Notification app launch details: %@", notificationAppLaunchDetails)
          result(notificationAppLaunchDetails)

        default:
          result(FlutterMethodNotImplemented)
    }
  }

  private func remoteMessageUserInfoToDict(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
      var message: [String: Any] = [:]
      var data: [String: Any] = [:]
      var notification: [String: Any] = [:]
      var notificationIOS: [String: Any] = [:]
      
      // message.data
      for (key, value) in userInfo {
          guard let keyString = key as? String else { continue }
          
          // message.messageId
          if keyString == "gcm.message_id" || keyString == "google.message_id" || keyString == "message_id" {
              message["messageId"] = value
              continue
          }
          
          // message.messageType
          if keyString == "message_type" {
              message["messageType"] = value
              continue
          }
          
          // message.collapseKey
          if keyString == "collapse_key" {
              message["collapseKey"] = value
              continue
          }
          
          // message.from
          if keyString == "from" {
              message["from"] = value
              continue
          }
          
          // message.sentTime
          if keyString == "google.c.a.ts" {
              message["sentTime"] = value
              continue
          }
          
          // message.to
          if keyString == "to" || keyString == "google.to" {
              message["to"] = value
              continue
          }
          
          // build data dict from remaining keys but skip keys that shouldn't be included in data
          if keyString == "aps" || keyString.hasPrefix("gcm.") || keyString.hasPrefix("google.") {
              continue
          }
          
          // message.apple.imageUrl
          if keyString == "fcm_options" {
              if let fcmOptions = value as? [String: Any],
                  let image = fcmOptions["image"] {
                  notificationIOS["imageUrl"] = image
              }
              continue
          }
          
          data[keyString] = value
      }
      message["data"] = data
      
      if let apsDict = userInfo["aps"] as? [String: Any] {
          // message.category
          if let category = apsDict["category"] {
              message["category"] = category
          }
          
          // message.threadId
          if let threadId = apsDict["thread-id"] {
              message["threadId"] = threadId
          }
          
          // message.contentAvailable
          if let contentAvailable = apsDict["content-available"] as? NSNumber {
              message["contentAvailable"] = contentAvailable.boolValue
          }
          
          // message.mutableContent
          if let mutableContent = apsDict["mutable-content"] as? NSNumber, mutableContent.intValue == 1 {
              message["mutableContent"] = mutableContent.boolValue
          }
          
          // message.notification.*
          if let alert = apsDict["alert"] {
              // can be a string or dictionary
              if let alertString = alert as? String {
                  // message.notification.title
                  notification["title"] = alertString
              } else if let apsAlertDict = alert as? [String: Any] {
                  // message.notification.title
                  if let title = apsAlertDict["title"] {
                      notification["title"] = title
                  }
                  
                  // message.notification.titleLocKey
                  if let titleLocKey = apsAlertDict["title-loc-key"] {
                      notification["titleLocKey"] = titleLocKey
                  }
                  
                  // message.notification.titleLocArgs
                  if let titleLocArgs = apsAlertDict["title-loc-args"] {
                      notification["titleLocArgs"] = titleLocArgs
                  }
                  
                  // message.notification.body
                  if let body = apsAlertDict["body"] {
                      notification["body"] = body
                  }
                  
                  // message.notification.bodyLocKey
                  if let bodyLocKey = apsAlertDict["loc-key"] {
                      notification["bodyLocKey"] = bodyLocKey
                  }
                  
                  // message.notification.bodyLocArgs
                  if let bodyLocArgs = apsAlertDict["loc-args"] {
                      notification["bodyLocArgs"] = bodyLocArgs
                  }
                  
                  // Apple only
                  // message.notification.apple.subtitle
                  if let subtitle = apsAlertDict["subtitle"] {
                      notificationIOS["subtitle"] = subtitle
                  }
                  
                  // Apple only
                  // message.notification.apple.subtitleLocKey
                  if let subtitleLocKey = apsAlertDict["subtitle-loc-key"] {
                      notificationIOS["subtitleLocKey"] = subtitleLocKey
                  }
                  
                  // Apple only
                  // message.notification.apple.subtitleLocArgs
                  if let subtitleLocArgs = apsAlertDict["subtitle-loc-args"] {
                      notificationIOS["subtitleLocArgs"] = subtitleLocArgs
                  }
              }
              
              // Apple only
              // message.notification.apple.badge
              if let badge = apsDict["badge"] {
                  notificationIOS["badge"] = String(describing: badge)
              }
              
              notification["apple"] = notificationIOS
              message["notification"] = notification
          }
          
          // message.notification.apple.sound
          if let sound = apsDict["sound"] {
              if let soundString = sound as? String {
                  // message.notification.apple.sound
                  notificationIOS["sound"] = [
                      "name": soundString,
                      "critical": false,
                      "volume": 1
                  ]
              } else if let apsSoundDict = sound as? [String: Any] {
                  var notificationIOSSound: [String: Any] = [:]
                  
                  // message.notification.apple.sound.name String
                  if let name = apsSoundDict["name"] {
                      notificationIOSSound["name"] = name
                  }
                  
                  // message.notification.apple.sound.critical Boolean
                  if let critical = apsSoundDict["critical"] as? NSNumber {
                      notificationIOSSound["critical"] = critical.boolValue
                  }
                  
                  // message.notification.apple.sound.volume Number
                  if let volume = apsSoundDict["volume"] {
                      notificationIOSSound["volume"] = volume
                  }
                  
                  // message.notification.apple.sound
                  notificationIOS["sound"] = notificationIOSSound
              }
              
              notification["apple"] = notificationIOS
              message["notification"] = notification
          }
      }
      
      return message
  }

}


extension String {
    var toDouble: Double {
        return Double(self) ?? 0.0
    }
}

extension Data {
    init(hexString: String) {
        self = hexString
            .dropFirst(hexString.hasPrefix("0x") ? 2 : 0)
            .compactMap { $0.hexDigitValue.map { UInt8($0) } }
            .reduce(into: (data: Data(capacity: hexString.count / 2), byte: nil as UInt8?)) { partialResult, nibble in
                if let p = partialResult.byte {
                    partialResult.data.append(p + nibble)
                    partialResult.byte = nil
                } else {
                    partialResult.byte = nibble << 4
                }
            }.data
    }
}
