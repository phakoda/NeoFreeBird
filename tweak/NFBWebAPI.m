//
//  NFBWebAPI.m
//  NeoFreeBird
//
//  Direct Twitter API v2 client with OAuth 1.0a signing.
//  Posts tweets directly from the app, bypassing attestation.
//

#import "NFBWebAPI.h"

// Twitter API v2 endpoints
static NSString *const kTwitterAPITweetURL = @"https://api.twitter.com/2/tweets";
static NSString *const kTwitterAPIVerifyURL = @"https://api.twitter.com/2/users/me";

@implementation NFBWebAPI

#pragma mark - Public Methods

+ (BOOL)isEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:@"webapi_tweet_enabled"];
    NSString *consumerKey = [defaults stringForKey:@"webapi_consumer_key"];
    NSString *consumerSecret = [defaults stringForKey:@"webapi_consumer_secret"];
    NSString *accessToken = [defaults stringForKey:@"webapi_access_token"];
    NSString *accessSecret = [defaults stringForKey:@"webapi_access_secret"];
    return enabled && consumerKey.length > 0 && consumerSecret.length > 0
        && accessToken.length > 0 && accessSecret.length > 0;
}

+ (void)postTweetWithText:(NSString *)text
                replyToID:(nullable NSString *)replyToID
             quoteTweetID:(nullable NSString *)quoteTweetID
               completion:(void(^)(BOOL success, NSString * _Nullable errorMessage))completion {

    if (![self isEnabled]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"Twitter API credentials not configured. Go to NeoFreeBird Settings → Web API Tweeting.");
        });
        return;
    }

    // Build JSON payload
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    if (text.length > 0) {
        payload[@"text"] = text;
    }

    if (replyToID.length > 0) {
        payload[@"reply"] = @{ @"in_reply_to_tweet_id": replyToID };
    }

    if (quoteTweetID.length > 0) {
        payload[@"quote_tweet_id"] = quoteTweetID;
    }

    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, [NSString stringWithFormat:@"JSON error: %@", jsonError.localizedDescription]);
        });
        return;
    }

    // Build request
    NSURL *url = [NSURL URLWithString:kTwitterAPITweetURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = jsonData;
    request.timeoutInterval = 30.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    // Generate and set OAuth header
    NSString *authHeader = [self oauthHeaderForMethod:@"POST" url:kTwitterAPITweetURL params:nil];
    [request setValue:authHeader forHTTPHeaderField:@"Authorization"];

    // Execute request
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(NO, [NSString stringWithFormat:@"Network error: %@", error.localizedDescription]);
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSDictionary *responseJSON = nil;
            if (data) {
                responseJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }

            if (httpResponse.statusCode == 201 || httpResponse.statusCode == 200) {
                // Success
                NSString *tweetId = responseJSON[@"data"][@"id"];
                NSString *msg = tweetId ? [NSString stringWithFormat:@"Tweet posted! ID: %@", tweetId] : @"Tweet posted!";
                completion(YES, msg);
            } else {
                // Error - extract message
                NSString *errorMsg = [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode];

                if (responseJSON[@"detail"]) {
                    errorMsg = responseJSON[@"detail"];
                } else if (responseJSON[@"errors"]) {
                    NSArray *errors = responseJSON[@"errors"];
                    if (errors.count > 0 && errors[0][@"message"]) {
                        errorMsg = errors[0][@"message"];
                    }
                } else if (responseJSON[@"title"]) {
                    errorMsg = responseJSON[@"title"];
                }

                // Add status code context
                if (httpResponse.statusCode == 401) {
                    errorMsg = [NSString stringWithFormat:@"Authentication failed: %@. Check your API credentials.", errorMsg];
                } else if (httpResponse.statusCode == 403) {
                    errorMsg = [NSString stringWithFormat:@"Forbidden: %@. Make sure your app has Read+Write permissions.", errorMsg];
                } else if (httpResponse.statusCode == 429) {
                    errorMsg = @"Rate limited. Please wait a moment and try again.";
                }

                completion(NO, errorMsg);
            }
        });
    }];
    [task resume];
}

+ (void)testCredentials:(void(^)(BOOL success, NSString * _Nullable message))completion {
    if (![self isEnabled]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"Please fill in all 4 API credential fields first.");
        });
        return;
    }

    NSURL *url = [NSURL URLWithString:kTwitterAPIVerifyURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 10.0;

    NSString *authHeader = [self oauthHeaderForMethod:@"GET" url:kTwitterAPIVerifyURL params:nil];
    [request setValue:authHeader forHTTPHeaderField:@"Authorization"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(NO, [NSString stringWithFormat:@"Connection failed: %@", error.localizedDescription]);
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200 && data) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSString *username = json[@"data"][@"username"];
                if (username) {
                    completion(YES, [NSString stringWithFormat:@"Authenticated as @%@", username]);
                } else {
                    completion(YES, @"Credentials verified!");
                }
            } else {
                NSString *msg = [NSString stringWithFormat:@"Authentication failed (HTTP %ld). Check your credentials.", (long)httpResponse.statusCode];
                completion(NO, msg);
            }
        });
    }];
    [task resume];
}

#pragma mark - OAuth 1.0a Implementation

+ (NSString *)oauthHeaderForMethod:(NSString *)method
                               url:(NSString *)urlString
                            params:(nullable NSDictionary *)additionalParams {

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *consumerKey = [defaults stringForKey:@"webapi_consumer_key"] ?: @"";
    NSString *consumerSecret = [defaults stringForKey:@"webapi_consumer_secret"] ?: @"";
    NSString *accessToken = [defaults stringForKey:@"webapi_access_token"] ?: @"";
    NSString *accessSecret = [defaults stringForKey:@"webapi_access_secret"] ?: @"";

    // Generate nonce and timestamp
    NSString *nonce = [self generateNonce];
    NSString *timestamp = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];

    // OAuth parameters
    NSMutableDictionary *oauthParams = [NSMutableDictionary dictionary];
    oauthParams[@"oauth_consumer_key"] = consumerKey;
    oauthParams[@"oauth_nonce"] = nonce;
    oauthParams[@"oauth_signature_method"] = @"HMAC-SHA1";
    oauthParams[@"oauth_timestamp"] = timestamp;
    oauthParams[@"oauth_token"] = accessToken;
    oauthParams[@"oauth_version"] = @"1.0";

    // Combine all params for signature base
    NSMutableDictionary *allParams = [NSMutableDictionary dictionaryWithDictionary:oauthParams];
    if (additionalParams) {
        [allParams addEntriesFromDictionary:additionalParams];
    }

    // Create parameter string (sorted)
    NSArray *sortedKeys = [[allParams allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *paramPairs = [NSMutableArray array];
    for (NSString *key in sortedKeys) {
        [paramPairs addObject:[NSString stringWithFormat:@"%@=%@",
                               [self percentEncode:key],
                               [self percentEncode:allParams[key]]]];
    }
    NSString *paramString = [paramPairs componentsJoinedByString:@"&"];

    // Create signature base string
    NSString *signatureBase = [NSString stringWithFormat:@"%@&%@&%@",
                               [method uppercaseString],
                               [self percentEncode:urlString],
                               [self percentEncode:paramString]];

    // Create signing key
    NSString *signingKey = [NSString stringWithFormat:@"%@&%@",
                            [self percentEncode:consumerSecret],
                            [self percentEncode:accessSecret]];

    // Generate HMAC-SHA1 signature
    NSString *signature = [self hmacSHA1:signatureBase withKey:signingKey];

    // Build Authorization header
    NSString *authHeader = [NSString stringWithFormat:
        @"OAuth oauth_consumer_key=\"%@\", "
        @"oauth_nonce=\"%@\", "
        @"oauth_signature=\"%@\", "
        @"oauth_signature_method=\"HMAC-SHA1\", "
        @"oauth_timestamp=\"%@\", "
        @"oauth_token=\"%@\", "
        @"oauth_version=\"1.0\"",
        [self percentEncode:consumerKey],
        [self percentEncode:nonce],
        [self percentEncode:signature],
        [self percentEncode:timestamp],
        [self percentEncode:accessToken]];

    return authHeader;
}

#pragma mark - Crypto Helpers

+ (NSString *)generateNonce {
    NSMutableData *data = [NSMutableData dataWithLength:32];
    int result = SecRandomCopyBytes(kSecRandomDefault, 32, data.mutableBytes);
    if (result != errSecSuccess) {
        // Fallback: use UUID
        return [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    }
    // Convert to base64 and strip non-alphanumeric
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    NSCharacterSet *nonAlphanumeric = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    return [[base64 componentsSeparatedByCharactersInSet:nonAlphanumeric] componentsJoinedByString:@""];
}

+ (NSString *)hmacSHA1:(NSString *)data withKey:(NSString *)key {
    const char *cKey = [key cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cData = [data cStringUsingEncoding:NSUTF8StringEncoding];

    unsigned char result[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, cKey, strlen(cKey), cData, strlen(cData), result);

    NSData *hmacData = [NSData dataWithBytes:result length:CC_SHA1_DIGEST_LENGTH];
    return [hmacData base64EncodedStringWithOptions:0];
}

+ (NSString *)percentEncode:(NSString *)string {
    // RFC 5849 percent encoding (unreserved chars: A-Z a-z 0-9 - . _ ~)
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-._~"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

@end
