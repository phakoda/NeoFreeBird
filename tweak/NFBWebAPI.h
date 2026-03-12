//
//  NFBWebAPI.h
//  NeoFreeBird
//
//  Direct Twitter API v2 client with OAuth 1.0a signing.
//  Posts tweets directly from the app, bypassing attestation.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonHMAC.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFBWebAPI : NSObject

/// Check if direct API tweeting is enabled and credentials are configured
+ (BOOL)isEnabled;

/// Post a tweet via Twitter API v2 directly
/// @param text The tweet text content
/// @param replyToID Optional tweet ID this is a reply to
/// @param quoteTweetID Optional tweet ID being quoted
/// @param completion Called on main thread with success status and optional error message
+ (void)postTweetWithText:(NSString *)text
                replyToID:(nullable NSString *)replyToID
             quoteTweetID:(nullable NSString *)quoteTweetID
               completion:(void(^)(BOOL success, NSString * _Nullable errorMessage))completion;

/// Test the API credentials by verifying the authenticated user
/// @param completion Called on main thread with success status and message
+ (void)testCredentials:(void(^)(BOOL success, NSString * _Nullable message))completion;

#pragma mark - OAuth 1.0a Helpers

/// Generate OAuth 1.0a Authorization header for a request
+ (NSString *)oauthHeaderForMethod:(NSString *)method
                               url:(NSString *)url
                            params:(nullable NSDictionary *)params;

@end

NS_ASSUME_NONNULL_END
