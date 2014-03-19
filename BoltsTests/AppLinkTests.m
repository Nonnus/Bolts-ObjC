//
//  AppLinkTests.m
//  Bolts
//
//  Created by David Poll on 3/10/14.
//  Copyright (c) 2014 Parse Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "Bolts.h"
#import "BFWebViewAppLinkResolver.h"

NSMutableArray *openedUrls = nil;

@interface AppLinkTests : XCTestCase

@end

@implementation AppLinkTests

- (NSString *)stringByEscapingQueryString:(NSString *)string {
    return (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                                 (CFStringRef)string,
                                                                                 NULL,
                                                                                 (CFStringRef)@":/?#[]@!$&'()*+,;=",
                                                                                 kCFStringEncodingUTF8));
}

- (NSURL *)dataUrlForHtml:(NSString *)html {
    NSString *encoded = [self stringByEscapingQueryString:html];
    NSString *urlString = [NSString stringWithFormat:@"data:text/html,%@", encoded];
    return [NSURL URLWithString:urlString];
}

/*!
 Swizzled-in replacement for UIApplication openUrl so that we can capture results.
 */
- (BOOL)openURLReplacement:(NSURL *)url {
    [openedUrls addObject:url];
    return YES;
}

/*!
 Produces HTML with meta tags using the keys and values from the content dictionaries
 of the array as the property and content, respectively.
 */
- (NSString *)htmlWithMetaTags:(NSArray *)tags {
    NSMutableString *html = [NSMutableString stringWithString:@"<html><head>"];
    
    for (NSDictionary *dict in tags) {
        for (NSString *key in dict) {
            if (dict[key] == [NSNull null]) {
                [html appendFormat:@"<meta property=\"%@\">", key];
            } else {
                [html appendFormat:@"<meta property=\"%@\" content=\"%@\">", key, dict[key]];
            }
        }
    }
    
    [html appendString:@"</head><body>Hello, world!</body><html>"];
    return html;
}

- (void)waitForTaskOnMainThread:(BFTask *)task {
    while (!task.isCompleted) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
}

- (void)setUp {
    [super setUp];
    openedUrls = [NSMutableArray array];
    
    // Swizzle the openUrl method so we can inspect its usage.
    Method originalMethod = class_getInstanceMethod([UIApplication class], @selector(openURL:));
    Method newMethod = class_getInstanceMethod([self class], @selector(openURLReplacement:));
    method_exchangeImplementations(originalMethod, newMethod);
}

- (void)tearDown {
    // Un-swizzle openUrl.
    Method originalMethod = class_getInstanceMethod([UIApplication class], @selector(openURL:));
    Method newMethod = class_getInstanceMethod([self class], @selector(openURLReplacement:));
    method_exchangeImplementations(originalMethod, newMethod);
    
    openedUrls = nil;
    
    [super tearDown];
}

#pragma mark openURL parsing

- (void)testSimpleOpenedURL {
    NSURL *url = [NSURL URLWithString:@"http://www.example.com"];
    
    BFURL *openedUrl = [BFURL openedURLFromURL:url];
    
    XCTAssertEqualObjects(url, openedUrl.targetURL);
    XCTAssertEqualObjects(openedUrl.targetURL, openedUrl.originalURL);
    XCTAssertEqual((NSUInteger)0, openedUrl.targetQueryParameters.count);
    XCTAssertEqual((NSUInteger)0, openedUrl.originalQueryParameters.count);
}

- (void)testOpenedURLWithQueryParameters {
    NSURL *url = [NSURL URLWithString:@"http://www.example.com?foo&bar=baz&space=%20"];
    
    BFURL *openedUrl = [BFURL openedURLFromURL:url];
    
    XCTAssertEqualObjects(url, openedUrl.targetURL);
    XCTAssertEqualObjects(openedUrl.targetURL, openedUrl.originalURL);
    XCTAssertEqual((NSUInteger)3, openedUrl.targetQueryParameters.count);
    XCTAssertEqual((NSUInteger)3, openedUrl.originalQueryParameters.count);
    XCTAssertEqualObjects([NSNull null], openedUrl.targetQueryParameters[@"foo"]);
    XCTAssertEqualObjects(@"baz", openedUrl.targetQueryParameters[@"bar"]);
    XCTAssertEqualObjects(@" ", openedUrl.targetQueryParameters[@"space"]);
}

- (void)testOpenedURLWithBlankQuery {
    NSURL *url = [NSURL URLWithString:@"http://www.example.com?"];
    
    BFURL *openedUrl = [BFURL openedURLFromURL:url];
    
    XCTAssertEqualObjects(url, openedUrl.targetURL);
    XCTAssertEqualObjects(openedUrl.targetURL, openedUrl.originalURL);
    XCTAssertEqual((NSUInteger)0, openedUrl.targetQueryParameters.count);
    XCTAssertEqual((NSUInteger)0, openedUrl.originalQueryParameters.count);
}

- (void)testOpenedURLWithAppLink {
    NSURL *url = [NSURL URLWithString:@"bolts://?al_applink_data=%7B%22user_agent%22%3A%22Bolts%20iOS%201.0.0%22%2C%22target_url%22%3A%22http%3A%5C%2F%5C%2Fwww.example.com%5C%2Fpath%22%7D"];
    
    BFURL *openedURL = [BFURL openedURLFromURL:url];
    XCTAssertEqualObjects(@"http://www.example.com/path", openedURL.targetURL.absoluteString);
    XCTAssert(openedURL.appLinkNavigationData[@"user_agent"]);
    XCTAssertEqualObjects(url.absoluteString, openedURL.originalURL.absoluteString);
}

- (void)testOpenedURLWithAppLinkTargetHasQueryParameters {
    NSURL *url = [NSURL URLWithString:@"bolts://?al_applink_data=%7B%22user_agent%22%3A%22Bolts%20iOS%201.0.0%22%2C%22target_url%22%3A%22http%3A%5C%2F%5C%2Fwww.example.com%5C%2Fpath%3Ffoo%3Dbar%22%7D"];
    
    BFURL *openedURL = [BFURL openedURLFromURL:url];
    XCTAssertEqualObjects(@"http://www.example.com/path?foo=bar", openedURL.targetURL.absoluteString);
    XCTAssertEqualObjects(@"bar", openedURL.targetQueryParameters[@"foo"]);
    XCTAssert(openedURL.appLinkNavigationData[@"user_agent"]);
    XCTAssertEqualObjects(url.absoluteString, openedURL.originalURL.absoluteString);
}

- (void)testOpenedURLWithAppLinkTargetAndLinkURLHasQueryParameters {
    NSURL *url = [NSURL URLWithString:@"bolts://?foo=bar&al_applink_data=%7B%22user_agent%22%3A%22Bolts%20iOS%201.0.0%22%2C%22target_url%22%3A%22http%3A%5C%2F%5C%2Fwww.example.com%5C%2Fpath%3Fbaz%3Dbat%22%7D"];
    
    BFURL *openedURL = [BFURL openedURLFromURL:url];
    XCTAssertEqualObjects(@"http://www.example.com/path?baz=bat", openedURL.targetURL.absoluteString);
    XCTAssertEqualObjects(@"bat", openedURL.targetQueryParameters[@"baz"]);
    XCTAssertEqualObjects(@"bar", openedURL.originalQueryParameters[@"foo"]);
    XCTAssert(openedURL.appLinkNavigationData[@"user_agent"]);
    XCTAssertEqualObjects(url.absoluteString, openedURL.originalURL.absoluteString);
}

- (void)testOpenedURLWithAppLinkWithCustomAppLinkData {
    NSURL *url = [NSURL URLWithString:@"bolts://?foo=bar&al_applink_data=%7B%22a%22%3A%22b%22%2C%22user_agent%22%3A%22Bolts%20iOS%201.0.0%22%2C%22target_url%22%3A%22http%3A%5C%2F%5C%2Fwww.example.com%5C%2Fpath%3Fbaz%3Dbat%22%7D"];
    
    BFURL *openedURL = [BFURL openedURLFromURL:url];
    XCTAssertEqualObjects(@"http://www.example.com/path?baz=bat", openedURL.targetURL.absoluteString);
    XCTAssertEqualObjects(@"bat", openedURL.targetQueryParameters[@"baz"]);
    XCTAssertEqualObjects(@"bar", openedURL.originalQueryParameters[@"foo"]);
    XCTAssertEqualObjects(@"b", openedURL.appLinkNavigationData[@"a"]);
    XCTAssert(openedURL.appLinkNavigationData[@"user_agent"]);
    XCTAssertEqualObjects(url.absoluteString, openedURL.originalURL.absoluteString);
}

#pragma mark WebView App Link resolution

- (void)testWebViewSimpleAppLinkParsing {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [[BFWebViewAppLinkResolver sharedInstance] appLinkFromURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)1, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    XCTAssertEqualObjects(url, link.webURL);
}

- (void)testWebViewAppLinkParsingFailure {
    BFTask *task = [[BFWebViewAppLinkResolver sharedInstance] appLinkFromURLInBackground:[NSURL URLWithString:@"http://badurl"]];
    [self waitForTaskOnMainThread:task];
    
    XCTAssertNotNil(task.error);
}

- (void)testWebViewSimpleAppLinkParsingNoneWebUrl {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345",
                                                  @"al:web:url": @"none"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [[BFWebViewAppLinkResolver sharedInstance] appLinkFromURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)1, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    XCTAssertNil(link.webURL);
}

- (void)testWebViewSimpleAppLinkParsingEmptyWebUrl {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345",
                                                  @"al:web:url": @""
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [[BFWebViewAppLinkResolver sharedInstance] appLinkFromURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)1, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    XCTAssertNil(link.webURL);
}

- (void)testWebViewSimpleAppLinkParsingWithWebUrl {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345",
                                                  @"al:web:url": @"http://www.example.com"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [[BFWebViewAppLinkResolver sharedInstance] appLinkFromURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)1, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    XCTAssertEqualObjects([NSURL URLWithString:@"http://www.example.com"], link.webURL);
}

- (void)testWebViewVersionedAppLinkParsing {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345"
                                                  },
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts2://",
                                                  @"al:ios:app_name": @"Bolts2",
                                                  @"al:ios:app_store_id": @"67890"
                                                  },
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [[BFWebViewAppLinkResolver sharedInstance] appLinkFromURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)2, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    target = link.targets[1];
    XCTAssertEqualObjects(@"bolts2://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts2", target.appName);
    XCTAssertEqualObjects(@"67890", target.appStoreId);
    
    XCTAssertEqualObjects(url, link.webURL);
}

- (void)testWebViewVersionedAppLinkParsingOnlyUrls {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{
                                                  @"al:ios:url": @"bolts://"
                                                  },
                                              @{
                                                  @"al:ios:url": @"bolts2://"
                                                  },
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [[BFWebViewAppLinkResolver sharedInstance] appLinkFromURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)2, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    
    target = link.targets[1];
    XCTAssertEqualObjects(@"bolts2://", target.URL.absoluteString);
    
    XCTAssertEqualObjects(url, link.webURL);
}

- (void)testWebViewVersionedAppLinkParsingUrlsAndNames {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{
                                                  @"al:ios:url": @"bolts://"
                                                  },
                                              @{
                                                  @"al:ios:url": @"bolts2://"
                                                  },
                                              @{
                                                  @"al:ios:app_name": @"Bolts"
                                                  },
                                              @{
                                                  @"al:ios:app_name": @"Bolts2"
                                                  },
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [[BFWebViewAppLinkResolver sharedInstance] appLinkFromURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)2, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    
    target = link.targets[1];
    XCTAssertEqualObjects(@"bolts2://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts2", target.appName);
    
    XCTAssertEqualObjects(url, link.webURL);
}

- (void)testWebViewPlatformFiltering {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345"
                                                  },
                                              @{ @"al:iphone": [NSNull null] },
                                              @{
                                                  @"al:iphone:url": @"bolts2://iphone",
                                                  @"al:iphone:app_name": @"Bolts2",
                                                  @"al:iphone:app_store_id": @"67890"
                                                  },
                                              @{ @"al:ipad": [NSNull null] },
                                              @{
                                                  @"al:ipad:url": @"bolts2://ipad",
                                                  @"al:ipad:app_name": @"Bolts2",
                                                  @"al:ipad:app_store_id": @"67890"
                                                  },
                                              @{ @"al:android": [NSNull null] },
                                              @{
                                                  @"al:android:url": @"bolts2://android",
                                                  @"al:android:package": @"com.bolts2",
                                                  },
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [[BFWebViewAppLinkResolver sharedInstance] appLinkFromURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)2, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    // Platform-specific links should be prioritized
    switch (UI_USER_INTERFACE_IDIOM()) {
        case UIUserInterfaceIdiomPhone:
            XCTAssertEqualObjects(@"bolts2://iphone", target.URL.absoluteString);
            break;
        case UIUserInterfaceIdiomPad:
            XCTAssertEqualObjects(@"bolts2://ipad", target.URL.absoluteString);
            break;
        default:
            break;
    }
    XCTAssertEqualObjects(@"Bolts2", target.appName);
    XCTAssertEqualObjects(@"67890", target.appStoreId);
    
    target = link.targets[1];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    
    XCTAssertEqualObjects(url, link.webURL);
}

#pragma mark App link meta tag parsing

- (void)testSimpleAppLinkParsing {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest resolveAppLinkInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)1, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    XCTAssertEqualObjects(url, link.webURL);
}

- (void)testAppLinkParsingFailure {
    BFTask *task = [BFAppLinkRequest resolveAppLinkInBackground:[NSURL URLWithString:@"http://badurl"]];
    [self waitForTaskOnMainThread:task];
    
    XCTAssertNotNil(task.error);
}

- (void)testSimpleAppLinkParsingNoneWebUrl {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345",
                                                  @"al:web:url": @"none"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest resolveAppLinkInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)1, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    XCTAssertNil(link.webURL);
}

- (void)testSimpleAppLinkParsingEmptyWebUrl {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345",
                                                  @"al:web:url": @""
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest resolveAppLinkInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)1, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    XCTAssertNil(link.webURL);
}

- (void)testSimpleAppLinkParsingWithWebUrl {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345",
                                                  @"al:web:url": @"http://www.example.com"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest resolveAppLinkInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)1, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    XCTAssertEqualObjects([NSURL URLWithString:@"http://www.example.com"], link.webURL);
}

- (void)testVersionedAppLinkParsing {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345"
                                                  },
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts2://",
                                                  @"al:ios:app_name": @"Bolts2",
                                                  @"al:ios:app_store_id": @"67890"
                                                  },
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest resolveAppLinkInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)2, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    target = link.targets[1];
    XCTAssertEqualObjects(@"bolts2://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts2", target.appName);
    XCTAssertEqualObjects(@"67890", target.appStoreId);
    
    XCTAssertEqualObjects(url, link.webURL);
}

- (void)testVersionedAppLinkParsingOnlyUrls {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{
                                                  @"al:ios:url": @"bolts://"
                                                  },
                                              @{
                                                  @"al:ios:url": @"bolts2://"
                                                  },
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest resolveAppLinkInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)2, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    
    target = link.targets[1];
    XCTAssertEqualObjects(@"bolts2://", target.URL.absoluteString);
    
    XCTAssertEqualObjects(url, link.webURL);
}

- (void)testVersionedAppLinkParsingUrlsAndNames {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{
                                                  @"al:ios:url": @"bolts://"
                                                  },
                                              @{
                                                  @"al:ios:url": @"bolts2://"
                                                  },
                                              @{
                                                  @"al:ios:app_name": @"Bolts"
                                                  },
                                              @{
                                                  @"al:ios:app_name": @"Bolts2"
                                                  },
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest resolveAppLinkInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)2, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    
    target = link.targets[1];
    XCTAssertEqualObjects(@"bolts2://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts2", target.appName);
    
    XCTAssertEqualObjects(url, link.webURL);
}

- (void)testPlatformFiltering {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{ @"al:ios": [NSNull null] },
                                              @{
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345"
                                                  },
                                              @{ @"al:iphone": [NSNull null] },
                                              @{
                                                  @"al:iphone:url": @"bolts2://iphone",
                                                  @"al:iphone:app_name": @"Bolts2",
                                                  @"al:iphone:app_store_id": @"67890"
                                                  },
                                              @{ @"al:ipad": [NSNull null] },
                                              @{
                                                  @"al:ipad:url": @"bolts2://ipad",
                                                  @"al:ipad:app_name": @"Bolts2",
                                                  @"al:ipad:app_store_id": @"67890"
                                                  },
                                              @{ @"al:android": [NSNull null] },
                                              @{
                                                  @"al:android:url": @"bolts2://ipad",
                                                  @"al:android:package": @"com.bolts2",
                                                  },
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest resolveAppLinkInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLink *link = task.result;
    XCTAssertEqual((NSUInteger)2, link.targets.count);
    
    BFAppLinkTarget *target = link.targets[0];
    // Platform-specific links should be prioritized
    switch (UI_USER_INTERFACE_IDIOM()) {
        case UIUserInterfaceIdiomPhone:
            XCTAssertEqualObjects(@"bolts2://iphone", target.URL.absoluteString);
            break;
        case UIUserInterfaceIdiomPad:
            XCTAssertEqualObjects(@"bolts2://ipad", target.URL.absoluteString);
            break;
        default:
            break;
    }
    XCTAssertEqualObjects(@"Bolts2", target.appName);
    XCTAssertEqualObjects(@"67890", target.appStoreId);
    
    target = link.targets[1];
    XCTAssertEqualObjects(@"bolts://", target.URL.absoluteString);
    XCTAssertEqualObjects(@"Bolts", target.appName);
    XCTAssertEqualObjects(@"12345", target.appStoreId);
    
    
    XCTAssertEqualObjects(url, link.webURL);
}

#pragma mark App link navigation

- (void)testSimpleAppLinkNavigation {
    BFAppLinkTarget *target = [BFAppLinkTarget appLinkTargetWithURL:[NSURL URLWithString:@"bolts://"]
                                                         appStoreId:@"12345"
                                                            appName:@"Bolts"];
    BFAppLink *appLink = [BFAppLink appLinkWithSourceURL:[NSURL URLWithString:@"http://www.example.com/path"]
                                                 targets:@[target]
                                                  webURL:[NSURL URLWithString:@"http://www.example.com/path"]];
    BFAppLinkNavigationType navigationType = [BFAppLinkRequest navigateToAppLink:appLink error:nil];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeApp);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    BFURL *parsedLink = [BFURL openedURLFromURL:openedUrl];
    XCTAssertEqualObjects(@"http://www.example.com/path", parsedLink.targetURL.absoluteString);
}

- (void)testSimpleAppLinkNavigationWithNavigationData {
    BFAppLinkTarget *target = [BFAppLinkTarget appLinkTargetWithURL:[NSURL URLWithString:@"bolts://"]
                                                         appStoreId:@"12345"
                                                            appName:@"Bolts"];
    BFAppLink *appLink = [BFAppLink appLinkWithSourceURL:[NSURL URLWithString:@"http://www.example.com/path"]
                                                 targets:@[target]
                                                  webURL:[NSURL URLWithString:@"http://www.example.com/path"]];
    BFAppLinkRequest *navigation = [BFAppLinkRequest navigationWithAppLink:appLink
                                                                         appData:nil
                                                                  navigationData:@{@"foo": @"bar"}];
    BFAppLinkNavigationType navigationType = [navigation navigate:nil];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeApp);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    BFURL *parsedLink = [BFURL openedURLFromURL:openedUrl];
    XCTAssertEqualObjects(@"http://www.example.com/path", parsedLink.targetURL.absoluteString);
    XCTAssertEqualObjects(@"bar", parsedLink.appLinkNavigationData[@"foo"]);
}

- (void)testSimpleAppLinkNavigationWithAppData {
    BFAppLinkTarget *target = [BFAppLinkTarget appLinkTargetWithURL:[NSURL URLWithString:@"bolts://"]
                                                         appStoreId:@"12345"
                                                            appName:@"Bolts"];
    BFAppLink *appLink = [BFAppLink appLinkWithSourceURL:[NSURL URLWithString:@"http://www.example.com/path"]
                                                 targets:@[target]
                                                  webURL:[NSURL URLWithString:@"http://www.example.com/path"]];
    BFAppLinkRequest *navigation = [BFAppLinkRequest navigationWithAppLink:appLink
                                                                         appData:@{@"foo": @"bar"}
                                                                  navigationData:nil];
    BFAppLinkNavigationType navigationType = [navigation navigate:nil];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeApp);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    BFURL *parsedLink = [BFURL openedURLFromURL:openedUrl];
    XCTAssertEqualObjects(@"http://www.example.com/path", parsedLink.targetURL.absoluteString);
    XCTAssertEqualObjects(@"bar", parsedLink.appLinkAppData[@"foo"]);
}

- (void)testSimpleAppLinkNavigationWithAppDataAndNavigationData {
    BFAppLinkTarget *target = [BFAppLinkTarget appLinkTargetWithURL:[NSURL URLWithString:@"bolts://"]
                                                         appStoreId:@"12345"
                                                            appName:@"Bolts"];
    BFAppLink *appLink = [BFAppLink appLinkWithSourceURL:[NSURL URLWithString:@"http://www.example.com/path"]
                                                 targets:@[target]
                                                  webURL:[NSURL URLWithString:@"http://www.example.com/path"]];
    BFAppLinkRequest *navigation = [BFAppLinkRequest navigationWithAppLink:appLink
                                                                         appData:@{@"foo": @"bar1"}
                                                                  navigationData:@{@"foo": @"bar2"}];
    BFAppLinkNavigationType navigationType = [navigation navigate:nil];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeApp);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    BFURL *parsedLink = [BFURL openedURLFromURL:openedUrl];
    XCTAssertEqualObjects(@"http://www.example.com/path", parsedLink.targetURL.absoluteString);
    XCTAssertEqualObjects(@"bar1", parsedLink.appLinkAppData[@"foo"]);
    XCTAssertEqualObjects(@"bar2", parsedLink.appLinkNavigationData[@"foo"]);
}

- (void)testAppLinkNavigationMultipleTargetsNoFallback {
    BFAppLinkTarget *target = [BFAppLinkTarget appLinkTargetWithURL:[NSURL URLWithString:@"bolts2://"]
                                                         appStoreId:@"67890"
                                                            appName:@"Bolts2"];
    BFAppLinkTarget *target2 = [BFAppLinkTarget appLinkTargetWithURL:[NSURL URLWithString:@"bolts://"]
                                                          appStoreId:@"12345"
                                                             appName:@"Bolts"];
    BFAppLink *appLink = [BFAppLink appLinkWithSourceURL:[NSURL URLWithString:@"http://www.example.com/path"]
                                                 targets:@[target, target2]
                                                  webURL:[NSURL URLWithString:@"http://www.example.com/path"]];
    BFAppLinkNavigationType navigationType = [BFAppLinkRequest navigateToAppLink:appLink error:nil];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeApp);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    BFURL *parsedLink = [BFURL openedURLFromURL:openedUrl];
    XCTAssertEqualObjects(@"http://www.example.com/path", parsedLink.targetURL.absoluteString);
    XCTAssert([openedUrl.absoluteString hasPrefix:@"bolts2://"]);
}

- (void)testAppLinkNavigationMultipleTargetsWithFallback {
    BFAppLinkTarget *target = [BFAppLinkTarget appLinkTargetWithURL:[NSURL URLWithString:@"bolts3://"]
                                                         appStoreId:@"67890"
                                                            appName:@"Bolts3"];
    BFAppLinkTarget *target2 = [BFAppLinkTarget appLinkTargetWithURL:[NSURL URLWithString:@"bolts://"]
                                                          appStoreId:@"12345"
                                                             appName:@"Bolts"];
    BFAppLink *appLink = [BFAppLink appLinkWithSourceURL:[NSURL URLWithString:@"http://www.example.com/path"]
                                                 targets:@[target, target2]
                                                  webURL:[NSURL URLWithString:@"http://www.example.com/path"]];
    BFAppLinkNavigationType navigationType = [BFAppLinkRequest navigateToAppLink:appLink error:nil];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeApp);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    BFURL *parsedLink = [BFURL openedURLFromURL:openedUrl];
    XCTAssertEqualObjects(@"http://www.example.com/path", parsedLink.targetURL.absoluteString);
    XCTAssert([openedUrl.absoluteString hasPrefix:@"bolts://"]);
}

- (void)testAppLinkNavigationNoTargets {
    BFAppLink *appLink = [BFAppLink appLinkWithSourceURL:[NSURL URLWithString:@"http://www.example.com/path"]
                                                 targets:@[]
                                                  webURL:[NSURL URLWithString:@"http://www.example.com/path"]];
    BFAppLinkNavigationType navigationType = [BFAppLinkRequest navigateToAppLink:appLink error:nil];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeBrowser);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    XCTAssertEqualObjects(@"http://www.example.com/path", openedUrl.absoluteString);
}

- (void)testAppLinkNavigationFailure {
    BFAppLink *appLink = [BFAppLink appLinkWithSourceURL:[NSURL URLWithString:@"http://www.example.com/path"]
                                                 targets:@[]
                                                  webURL:nil];
    BFAppLinkNavigationType navigationType = [BFAppLinkRequest navigateToAppLink:appLink error:nil];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeFailure);
    XCTAssertEqual((NSUInteger)0, openedUrls.count);
}

#pragma mark App link navigation integration tests

- (void)testSimpleAppLinkURLNavigation {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{
                                                  @"al:ios": [NSNull null],
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest navigateToURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLinkNavigationType navigationType = [task.result integerValue];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeApp);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    BFURL *parsedLink = [BFURL openedURLFromURL:openedUrl];
    XCTAssertEqualObjects(url.absoluteString, parsedLink.targetURL.absoluteString);
}

- (void)testAppLinkURLNavigationMultipleTargetsNoFallback {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{
                                                  @"al:ios": [NSNull null],
                                                  @"al:ios:url": @"bolts2://",
                                                  @"al:ios:app_name": @"Bolts2",
                                                  @"al:ios:app_store_id": @"67890"
                                                  },
                                              @{
                                                  @"al:ios": [NSNull null],
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest navigateToURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLinkNavigationType navigationType = [task.result integerValue];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeApp);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    BFURL *parsedLink = [BFURL openedURLFromURL:openedUrl];
    XCTAssertEqualObjects(url.absoluteString, parsedLink.targetURL.absoluteString);
    XCTAssert([openedUrl.absoluteString hasPrefix:@"bolts2://"]);
}

- (void)testAppLinkURLNavigationMultipleTargetsWithFallback {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{
                                                  @"al:ios": [NSNull null],
                                                  @"al:ios:url": @"bolts3://",
                                                  @"al:ios:app_name": @"Bolts3",
                                                  @"al:ios:app_store_id": @"67890"
                                                  },
                                              @{
                                                  @"al:ios": [NSNull null],
                                                  @"al:ios:url": @"bolts://",
                                                  @"al:ios:app_name": @"Bolts",
                                                  @"al:ios:app_store_id": @"12345"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest navigateToURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLinkNavigationType navigationType = [task.result integerValue];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeApp);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    BFURL *parsedLink = [BFURL openedURLFromURL:openedUrl];
    XCTAssertEqualObjects(url.absoluteString, parsedLink.targetURL.absoluteString);
    XCTAssert([openedUrl.absoluteString hasPrefix:@"bolts://"]);
}

- (void)testAppLinkURLNavigationNoTargets {
    NSString *html = [self htmlWithMetaTags:@[]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest navigateToURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLinkNavigationType navigationType = [task.result integerValue];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeBrowser);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    XCTAssertEqualObjects(url.absoluteString, openedUrl.absoluteString);
}

- (void)testAppLinkURLNavigationFallbackToWeb {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{
                                                  @"al:ios": [NSNull null],
                                                  @"al:ios:url": @"bad://",
                                                  @"al:ios:app_name": @"Bad",
                                                  @"al:ios:app_store_id": @"12345",
                                                  @"al:web:url": @"http://www.example.com"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest navigateToURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLinkNavigationType navigationType = [task.result integerValue];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeBrowser);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    XCTAssertEqualObjects(@"http://www.example.com", openedUrl.absoluteString);
}

- (void)testAppLinkURLNavigationWebLinkOnly {
    NSString *html = [self htmlWithMetaTags:@[
                                              @{
                                                  @"al:web:url": @"http://www.example.com"
                                                  }
                                              ]];
    NSURL *url = [self dataUrlForHtml:html];
    
    BFTask *task = [BFAppLinkRequest navigateToURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    BFAppLinkNavigationType navigationType = [task.result integerValue];
    
    XCTAssertEqual(navigationType, BFAppLinkNavigationTypeBrowser);
    XCTAssertEqual((NSUInteger)1, openedUrls.count);
    
    NSURL *openedUrl = openedUrls.firstObject;
    XCTAssertEqualObjects(@"http://www.example.com", openedUrl.absoluteString);
}

- (void)testAppLinkToBadUrl {
    NSURL *url = [NSURL URLWithString:@"http://badurl"];
    
    BFTask *task = [BFAppLinkRequest navigateToURLInBackground:url];
    [self waitForTaskOnMainThread:task];
    
    XCTAssertNotNil(task.error);
}

@end
