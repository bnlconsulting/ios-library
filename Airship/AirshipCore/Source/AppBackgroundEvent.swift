/* Copyright Airship and Contributors */

/**
 * - Note: For Internal use only :nodoc:
 */
@objc(UAAppBackgroundEvent)
class AppBackgroundEvent : AppExitEvent {
    @objc
    public override var eventType : String {
        get {
            return "app_background"
        }
    }
}
