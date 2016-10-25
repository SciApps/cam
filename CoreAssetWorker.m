//
//  CoreAssetWorker.m
//  CoreAssetManager
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import "CoreAssetManager.h"
#import "CoreAssetWorker.h"
#import "CoreAssetURLConnection.h"
#import <NUUtil/UtilMacros.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#if TARGET_OS_IPHONE
#import <CFNetwork/CFNetwork.h>
#endif

@interface CoreAssetWorkerSession : NSObject

@property (nonatomic, weak) CoreAssetWorker *worker;
@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic, strong) CoreAssetURLConnection *assetConnection;
@property (nonatomic) CFHTTPMessageRef cfRequest;
@property (nonatomic) CFReadStreamRef cfReadStream;

@end

@implementation CoreAssetWorkerSession

- (void)dealloc {
    CFRelease(_cfRequest);
    CFRelease(_cfReadStream);
}

- (void)initStream {
    if (_cfReadStream) {
        CFReadStreamClose(_cfReadStream);
        CFRelease(_cfReadStream);
    }
    
    _cfReadStream = CFReadStreamCreateForHTTPRequest(NULL, _cfRequest);
    
    CFReadStreamSetProperty(_cfReadStream, (__bridge CFStringRef _Nonnull)(@"_kCFStreamPropertyReadTimeout"), (__bridge CFTypeRef)(@(_request.timeoutInterval)));
    
    if ([_assetConnection.assetItem.class allowRedirect]) {
        CFReadStreamSetProperty(_cfReadStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
    }
    
    CFReadStreamOpen(_cfReadStream);
}

@end

typedef enum: NSUInteger {
    CoreAssetWorker_Initializing,
    CoreAssetWorker_SpawningThread
}
CoreAssetWorkerConditionLockValues;

NSString *kCoreAssetWorkerAssetItem = @"assetItem";
NSString *kCoreAssetWorkerAssetData = @"assetData";
NSString *kCoreAssetWorkerAssetPostprocessedData = @"assetPostprocessedData";

@interface CoreAssetWorker()

@property (nonatomic, strong) NSThread *thread;
@property (nonatomic, strong) NSRunLoop *runLoop;
@property (nonatomic, strong) NSConditionLock *threadLock;
@property (nonatomic, strong) NSMutableArray *downloadList;
@property (nonatomic, strong) NSNumber *downloadCount;
@property (nonatomic) BOOL cfInitialized;

@end

@implementation CoreAssetWorker

- (instancetype)init {
    self = [super init];
    
    if (self) {
        _terminate = NO;
        _terminateSpin = NO;
        
        _timeAll = 0;
        _timeCurrentStart = 0;
        _timeCurrent = 0;
        _sizeAll = 0;
        _sizeCurrent = 0;
        _bandwith = 0;
        
        _downloadCount = @(0);
        
        _threadLock = [[NSConditionLock alloc] initWithCondition:CoreAssetWorker_Initializing];
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(workerMain) object:nil];
        [_thread start];
        [_threadLock lockWhenCondition:CoreAssetWorker_SpawningThread];
    }
    
    return self;
}

- (void)workerMain {
    @autoreleasepool {
        [_threadLock lock];
        
        _runLoop = [NSRunLoop currentRunLoop];
        [_runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        
        [_threadLock unlockWithCondition:CoreAssetWorker_SpawningThread];
        
        while (!_terminateSpin && [_runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {
            _spinCount++;
        }
    }
}

- (void)sendDelegateFailedDownloadingAsset:(CoreAssetItemNormal *)assetItem {
    if ([_delegate respondsToSelector:@selector(failedDownloadingAsset:)]) {
        [_delegate performSelectorOnMainThread:@selector(failedDownloadingAsset:) withObject:@{kCoreAssetWorkerAssetItem:assetItem} waitUntilDone:NO];
    }
}

- (void)sendDelegateFinishedDownloadingAsset:(CoreAssetItemNormal *)assetItem connectionData:(NSData *)connectionData  {
    if ([_delegate respondsToSelector:@selector(finishedDownloadingAsset:)]) {
        id postprocessedData = [assetItem postProcessData:connectionData];
        
        CoreAssetManager *assetManager = [[assetItem.class parentCamClass] manager];
        
        if([assetManager determineLoginFailure:postprocessedData assetItem:assetItem]) {
            [assetManager.loginCondition lock];
            
            @synchronized (assetManager.loginCount) {
                NSUInteger count = assetManager.loginCount.unsignedIntegerValue;
                assetManager.loginCount = @(count + 1);
                
                if (!count) {
                    [assetManager performSelectorOnMainThread:@selector(performRelogin) withObject:nil waitUntilDone:NO];
                }
            }
            
            [assetManager.loginCondition wait];
            
            @synchronized (assetManager.loginSuccessful) {
                NSUInteger success = assetManager.loginSuccessful.unsignedIntegerValue;
            }
            
            [assetManager.loginCondition unlock];
        }
        
        [_delegate performSelectorOnMainThread:@selector(finishedDownloadingAsset:) withObject:@{kCoreAssetWorkerAssetItem:assetItem, kCoreAssetWorkerAssetData:connectionData, kCoreAssetWorkerAssetPostprocessedData:postprocessedData} waitUntilDone:NO];
    }
}

- (void)sendDelegateFinishedDownloadingAsset:(CoreAssetWorkerSession *)coreAssetWorkerSession  {
    if ([_delegate respondsToSelector:@selector(finishedDownloadingAsset:)]) {
        id postprocessedData = [coreAssetWorkerSession.assetConnection.assetItem postProcessData:coreAssetWorkerSession.assetConnection.connectionData];
        
        CoreAssetManager *assetManager = [[coreAssetWorkerSession.assetConnection.assetItem.class parentCamClass] manager];
        
        if([assetManager determineLoginFailure:postprocessedData assetItem:coreAssetWorkerSession.assetConnection.assetItem]) {
            [assetManager.loginCondition lock];
            
            @synchronized (assetManager.loginCount) {
                NSUInteger count = assetManager.loginCount.unsignedIntegerValue;
                assetManager.loginCount = @(count + 1);
                
                if (!count) {
                    [assetManager performSelectorOnMainThread:@selector(performRelogin) withObject:nil waitUntilDone:NO];
                }
            }
            
            if(![assetManager.loginCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:10]]) {
                TestLog(@"CoreAssetWorker: timeout reached");
                [_delegate performSelectorOnMainThread:@selector(failedDownloadingAsset:) withObject:@{kCoreAssetWorkerAssetItem:coreAssetWorkerSession.assetConnection.assetItem} waitUntilDone:NO];
                [assetManager.loginCondition unlock];
                
                @synchronized (assetManager.loginCount) {
                    NSUInteger count = assetManager.loginCount.unsignedIntegerValue;
                    assetManager.loginCount = @(count - 1);
                }
                
                return;
            }
            
            NSUInteger success;
            @synchronized (assetManager.loginSuccessful) {
                success = assetManager.loginSuccessful.unsignedIntegerValue;
            }
            
            [assetManager.loginCondition unlock];
            
            if (!success) {
                TestLog(@"CoreAssetWorker: unable to login");
                [_delegate performSelectorOnMainThread:@selector(failedDownloadingAsset:) withObject:@{kCoreAssetWorkerAssetItem:coreAssetWorkerSession.assetConnection.assetItem} waitUntilDone:NO];
            }
            else {
                coreAssetWorkerSession.assetConnection.connectionData = nil;
                coreAssetWorkerSession.request = [coreAssetWorkerSession.assetConnection.assetItem createURLRequest];
                //[self performSelector:@selector(rl_perform:) onThread:_thread withObject:coreAssetWorkerSession waitUntilDone:NO];
                [self _startDownload:coreAssetWorkerSession.assetConnection request:coreAssetWorkerSession.request];
            }
            
            @synchronized (assetManager.loginCount) {
                NSUInteger count = assetManager.loginCount.unsignedIntegerValue;
                assetManager.loginCount = @(count - 1);
            }
            
            return;
        }
        
        [_delegate performSelectorOnMainThread:@selector(finishedDownloadingAsset:) withObject:@{kCoreAssetWorkerAssetItem:coreAssetWorkerSession.assetConnection.assetItem, kCoreAssetWorkerAssetData:coreAssetWorkerSession.assetConnection.connectionData, kCoreAssetWorkerAssetPostprocessedData:postprocessedData} waitUntilDone:NO];
    }
}

- (void)_initCF {
    if (!_cfInitialized) {
        _downloadCount = @(0);
        _downloadList = [NSMutableArray new];
        _cfInitialized = YES;
    }
}

- (void)t_stop {
    @synchronized(self) {
        [_downloadList removeAllObjects];
    }
}

- (void)stop {
    _terminate = YES;
    [self performSelector:@selector(t_stop) onThread:_thread withObject:nil waitUntilDone:YES];
}

- (void)resume {
    //[self performSelector:@selector(t_resume) onThread:_thread withObject:nil waitUntilDone:NO];
}

- (BOOL)isBusy {
    @synchronized(self) {
        return _downloadCount.integerValue > 0;
    }
}

- (void)_checkNextDownload {
    CoreAssetURLConnection *assetConnection = _downloadList.firstObject;
    
    NSURLRequest *request = [assetConnection.assetItem createURLRequest];
    
    _timeCurrentStart = CACurrentMediaTime();
    _sizeCurrent = 0;
    _bandwith = 0;
    
    [self _startDownload:assetConnection request:request];
    
    //TestLog(@"_checkNextDownload: asset: '%@' class: '%@'", assetConnection.assetItem.assetName, NSStringFromClass([assetConnection.assetItem class]));
}

- (void)rl_perform:(CoreAssetWorkerSession *)coreAssetWorkerSession {
    if (_terminate) {
        @synchronized(self) {
            _downloadCount = @(_downloadCount.integerValue - 1);
        }
        return;
    }
    
    CoreAssetManager *assetManager = [[coreAssetWorkerSession.assetConnection.assetItem.class parentCamClass] manager];
    
    //CFTimeInterval startTime = CACurrentMediaTime();
    
    int attempts = 1;
    //UInt32 theResult = 0;
    CFHTTPMessageRef response = NULL;
    NSDictionary<NSString *, NSString *> *headerFields;
    
    while(assetManager.networkStatus != CAMNotReachable &&
          coreAssetWorkerSession.assetConnection.assetItem.retryCount &&
          (!coreAssetWorkerSession.assetConnection.connectionDataExpectedLength ||
                coreAssetWorkerSession.assetConnection.connectionData.length == coreAssetWorkerSession.assetConnection.connectionDataExpectedLength)) {
        
        [coreAssetWorkerSession initStream];
        coreAssetWorkerSession.assetConnection.connectionData = nil;
        
        if (response) {
            CFRelease(response);
            response = nil;
        }
        
        CFIndex numBytesRead = 0;
        UInt8 buf[16 * 1024] = { 0 };
        
        while (!response || numBytesRead) {
            numBytesRead = CFReadStreamRead(coreAssetWorkerSession.cfReadStream, buf, sizeof(buf));
            
            if (!response) {
                response = (CFHTTPMessageRef)CFReadStreamCopyProperty(coreAssetWorkerSession.cfReadStream, kCFStreamPropertyHTTPResponseHeader);
                
                headerFields = CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(response));
                
                [headerFields enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
                    if ([key caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame) {
                        coreAssetWorkerSession.assetConnection.connectionDataExpectedLength = obj.longLongValue;
                    }
                }];
                
                /*NSData *socketData = CFBridgingRelease(CFReadStreamCopyProperty(coreAssetWorkerSession.cfReadStream, kCFStreamPropertySocketNativeHandle));
                int* clientSocket = (int *)socketData.bytes;
                if (clientSocket) {
                    socklen_t len = sizeof(struct sockaddr_in);
                    struct sockaddr_in clientAddress;
                    getsockname(*clientSocket, &clientAddress, &len);
                    TestLog(@"port: %i", ntohs(clientAddress.sin_port));
                }*/
            }
            
            [coreAssetWorkerSession.assetConnection appendBytes:buf length:numBytesRead];
        }
        
        coreAssetWorkerSession.assetConnection.assetItem.retryCount--;
        attempts++;
    }
    
    UInt32 responseCode = response ? CFHTTPMessageGetResponseStatusCode(response) : 0;
    
    //CFReadStreamClose(coreAssetWorkerSession.cfReadStream);
    //CFRelease(coreAssetWorkerSession.cfReadStream);
    CFRelease(response);
    
    CoreAssetURLConnection *assetConnection = coreAssetWorkerSession.assetConnection;
    
    @synchronized(self) {
        _downloadCount = @(_downloadCount.integerValue - 1);
        
        if (_terminate) {
            return;
        }
        
        [_downloadList removeObject:assetConnection];
        
        if (!_terminate && _downloadList.count) {
            [self _checkNextDownload];
        }
        
        if (!assetConnection.connectionData) {
            assetConnection.connectionData = [NSMutableData new];
        }
        
        if (![assetConnection validLength] || (responseCode < 200 || responseCode >= 300)) {
            TestLog(@"CFNetworking: HTTP_CODE: %d (attempts: %i) Network Status: %d", responseCode, attempts, assetManager.networkStatus);
            [self sendDelegateFailedDownloadingAsset:assetConnection.assetItem];
        }
        else {
            if (assetConnection.connectionData.length) {
                if (assetConnection.assetItem.shouldCacheOnDisk) {
                    @try {
                        [assetConnection.assetItem store:assetConnection.connectionData];
                    }
                    @catch (NSException *exception) {
                        [self sendDelegateFailedDownloadingAsset:assetConnection.assetItem];
                        return;
                    }
                }
            }
            
            // storing the file takes lot of time, so check for termination request again
            if (_terminate) {
                [assetConnection.assetItem removeStoredFile];
                return;
            }
            
            [self sendDelegateFinishedDownloadingAsset:coreAssetWorkerSession];
        }
    }
}

- (void)_startDownload:(CoreAssetURLConnection *)assetConnection request:(NSURLRequest *)request {
    __block CoreAssetWorkerSession* coreAssetWorkerSession = [CoreAssetWorkerSession new];
    coreAssetWorkerSession.worker = self;
    coreAssetWorkerSession.request = request;
    coreAssetWorkerSession.assetConnection = assetConnection;
    coreAssetWorkerSession.cfRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, (__bridge CFStringRef _Nonnull)(request.HTTPMethod), (__bridge CFURLRef _Nonnull)(request.URL), kCFHTTPVersion1_1);
    
    CoreAssetManager *assetManager = [[coreAssetWorkerSession.assetConnection.assetItem.class parentCamClass] manager];
    
    // cookies
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSMutableString *cookieBuild = [NSMutableString new];
    NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSArray<NSHTTPCookie *> *requiredCookies = [cookieStorage.cookies filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"domain = %@", components.host]];
    for (NSHTTPCookie *cookie in requiredCookies) {
        if (cookieBuild.length) {
            [cookieBuild appendString:@";"];
        }
        
        [cookieBuild appendFormat:@"%@=%@", cookie.name, cookie.value];
    }
    
    if (cookieBuild.length) {
        CFHTTPMessageSetHeaderFieldValue(coreAssetWorkerSession.cfRequest, (__bridge CFStringRef _Nonnull)(@"Cookie"), (__bridge CFStringRef _Nullable)(cookieBuild));
    }
    
    // setup header
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
        CFHTTPMessageSetHeaderFieldValue(coreAssetWorkerSession.cfRequest, (__bridge CFStringRef _Nonnull)(key), (__bridge CFStringRef _Nullable)(obj));
    }];
    
    CFHTTPMessageSetHeaderFieldValue(coreAssetWorkerSession.cfRequest, (__bridge CFStringRef _Nullable)(@"Host"), (__bridge CFStringRef _Nullable)(components.host));
    
    if ([request.HTTPMethod isEqualToString:@"POST"] && request.HTTPBody.length) {
        CFHTTPMessageSetHeaderFieldValue(coreAssetWorkerSession.cfRequest, @"Content-Length", (__bridge CFStringRef _Nullable)([NSString stringWithFormat:@"%d", request.HTTPBody.length]));
        CFHTTPMessageSetBody(coreAssetWorkerSession.cfRequest, (__bridge CFDataRef _Nonnull)(request.HTTPBody));
    }
    
    // setup user agent
    NSString *userAgent = [assetManager.class userAgent];
    
    if (userAgent.length) {
        CFHTTPMessageSetHeaderFieldValue(coreAssetWorkerSession.cfRequest, (__bridge CFStringRef _Nullable)(@"User-Agent"), (__bridge CFStringRef _Nullable)(userAgent));
    }
    
    // setup keep alive
    //CFHTTPMessageSetHeaderFieldValue(coreAssetWorkerSession.cfRequest, (__bridge CFStringRef _Nullable)(@"Keep-Alive"), (__bridge CFStringRef _Nullable)(@"30"));
    
    _downloadCount = @(_downloadCount.integerValue + 1);
    
    //[self performSelector:@selector(rl_perform:) withObject:coreAssetWorkerSession afterDelay:0 inModes:@[NSRunLoopCommonModes]];
    [self performSelector:@selector(rl_perform:) onThread:_thread withObject:coreAssetWorkerSession waitUntilDone:NO];
}

- (void)rl_downloadAsset:(CoreAssetItemNormal *)asset {
    @synchronized(self) {
        CoreAssetURLConnection *assetConnection = [CoreAssetURLConnection new];
        assetConnection.assetItem = asset;
        
        if (_downloadCount.integerValue > 0) {
            [_downloadList addObject:assetConnection];
            return;
        }
        
        NSURLRequest *request = [asset createURLRequest];
        
        _timeCurrentStart = CACurrentMediaTime();
        _sizeCurrent = 0;
        _bandwith = 0;
        
        [self _initCF];
        [self _startDownload:assetConnection request:request];
    }
}

- (void)t_downloadAsset:(CoreAssetItemNormal *)asset {
    CFIndex count = _downloadCount.integerValue;
    
    if (count) {
        TestLog(@"t_downloadAsset count = %li", count);
    }
    
    [_runLoop performSelector:@selector(rl_downloadAsset:) target:self argument:asset order:0 modes:@[NSRunLoopCommonModes]];
}

- (void)downloadAsset:(CoreAssetItemNormal *)asset {
    // this is where the terminated worker woke up :)
    _terminate = NO;
    
    if (asset) {
        [self performSelector:@selector(t_downloadAsset:) onThread:_thread withObject:asset waitUntilDone:NO];
    }
}

@end
