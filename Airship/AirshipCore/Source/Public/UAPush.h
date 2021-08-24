/* Copyright Airship and Contributors */

@import UserNotifications;

/**
 * Notification options
 */
typedef NS_OPTIONS(NSUInteger, UANotificationOptions) {
    UANotificationOptionNone = 0,
    UANotificationOptionBadge   = (1 << 0),
    UANotificationOptionSound   = (1 << 1),
    UANotificationOptionAlert   = (1 << 2),
    UANotificationOptionCarPlay = (1 << 3),
    UANotificationOptionCriticalAlert = (1 << 4),
    UANotificationOptionProvidesAppNotificationSettings = (1 << 5),
    UANotificationOptionProvisional = (1 << 6),
    UANotificationOptionAnnouncement = (1 << 7),
};

/**
 * Authorized notification settings
 */
typedef NS_OPTIONS(NSUInteger, UAAuthorizedNotificationSettings) {
    UAAuthorizedNotificationSettingsNone = 0,
    UAAuthorizedNotificationSettingsBadge   = (1 << 0),
    UAAuthorizedNotificationSettingsSound   = (1 << 1),
    UAAuthorizedNotificationSettingsAlert   = (1 << 2),
    UAAuthorizedNotificationSettingsCarPlay = (1 << 3),
    UAAuthorizedNotificationSettingsLockScreen = (1 << 4),
    UAAuthorizedNotificationSettingsNotificationCenter = (1 << 5),
    UAAuthorizedNotificationSettingsCriticalAlert = (1 << 6),
    UAAuthorizedNotificationSettingsAnnouncement = (1 << 7),
};

/**
 * Authorization status
 */
typedef NS_ENUM(NSInteger, UAAuthorizationStatus) {
    UAAuthorizationStatusNotDetermined = 0,
    UAAuthorizationStatusDenied,
    UAAuthorizationStatusAuthorized,
    UAAuthorizationStatusProvisional,
    UAAuthorizationStatusEphemeral,
};
