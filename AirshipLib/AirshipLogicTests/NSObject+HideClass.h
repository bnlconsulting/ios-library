#import <Foundation/Foundation.h>

@interface NSObject (HideClass)

/**
 * Makes the class method 'class' return nil.
 */
+ (void)hideClass;

/**
 * Restores the class method 'class'.
 */
+ (void)revealClass;
@end
