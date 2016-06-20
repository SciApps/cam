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
#import "curl.h"
#import "CURLConnection.h"
#import "UtilMacros.h"

@interface CURLSession : NSObject

@property (nonatomic, weak) CoreAssetWorker *worker;
@property (nonatomic) CURL *curl;
@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic, strong) CoreAssetURLConnection *assetConnection;
@property (nonatomic, strong) NSString *proxyHost;
@property (nonatomic, strong) NSNumber *proxyPort;
@property (nonatomic) struct curl_slist *headers;
@property (nonatomic, strong) NSArray *headerList;
@property (nonatomic, strong) NSString *cookie;

@end

@implementation CURLSession

- (void)dealloc {
    curl_slist_free_all(_headers);
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
@property (nonatomic) CURL *curl;
@property (nonatomic, strong) NSMutableArray *curlDownloadList;
@property (nonatomic, strong) NSNumber *curlDownloadCount;

@end

int CoreAssetWorkerCurlDebugCallback(CURL *curl, curl_infotype infotype, char *info, size_t infoLen, void *contextInfo) {
    //CoreAssetWorker *assetWorker = (__bridge CoreAssetWorker *)contextInfo;
    NSData *infoData = [NSData dataWithBytes:info length:infoLen];
    NSString *infoStr = [[NSString alloc] initWithData:infoData encoding:NSUTF8StringEncoding];
    
    if (infoStr) {
        infoStr = [infoStr stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];	// convert Windows CR/LF to just LF
        infoStr = [infoStr stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];	// convert remaining CRs to LFs
        
        switch (infotype) {
            case CURLINFO_DATA_IN:
                TestLog(@"CURL: %@", infoStr);
                break;
            case CURLINFO_DATA_OUT:
                TestLog(@"CURL: %@", [infoStr stringByAppendingString:@"\n"]);
                break;
            case CURLINFO_HEADER_IN:
                TestLog(@"CURL: %@", [@"< " stringByAppendingString:infoStr]);
                break;
            case CURLINFO_HEADER_OUT:
                infoStr = [infoStr stringByReplacingOccurrencesOfString:@"\n" withString:@"\n> "];	// start each line with a /
                TestLog(@"CURL: %@", [NSString stringWithFormat:@"> %@\n", infoStr]);
                break;
            case CURLINFO_TEXT:
                TestLog(@"CURL: %@", [@"* " stringByAppendingString:infoStr]);
                break;
            default:	// ignore the other CURLINFOs
                break;
        }
    }
    
    return 0;
}

size_t CoreAssetWorkerCurlHeaderCallback(char *buffer, size_t size, size_t nmemb, void *userdata) {
    const size_t sizeInBytes = size * nmemb;
    CURLSession* curlSession = (__bridge CURLSession *)userdata;
    const char* contentLengthPrefix = "Content-Length: ";
    
    if (strstr(buffer, contentLengthPrefix)) {
        CoreAssetURLConnection *assetConnection = curlSession.assetConnection;
        size_t contentLengthPrefixLen = strlen(contentLengthPrefix);
        const char* lengthBegin = buffer + contentLengthPrefixLen;
        long contentLength = strtol(lengthBegin, NULL, 10);
        assetConnection.connectionDataExpectedLength = contentLength;
    }
    
    return sizeInBytes;
}

size_t CoreAssetWorkerCurlWriteCallback(char *ptr, size_t size, size_t nmemb, void *userdata) {
    const size_t sizeInBytes = size * nmemb;
    
    CURLSession* curlSession = (__bridge CURLSession *)userdata;
    CoreAssetURLConnection *assetConnection = curlSession.assetConnection;
    
    double contentLength = 0;
    curl_easy_getinfo(curlSession.curl, CURLINFO_CONTENT_LENGTH_DOWNLOAD, &contentLength);
    
    [assetConnection appendBytes:ptr length:sizeInBytes];
    
    @synchronized(curlSession.worker) {
        curlSession.worker.sizeCurrent += sizeInBytes;
        curlSession.worker.timeCurrent = CACurrentMediaTime() - curlSession.worker.timeCurrentStart;
        curlSession.worker.bandwith = (CGFloat)curlSession.worker.sizeCurrent / (CGFloat)curlSession.worker.timeCurrent;
    }
    
    return sizeInBytes;
}

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
        
        _curl = NULL;
        _curlDownloadCount = @(0);
        
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

- (void)sendDelegateFinishedDownloadingAsset:(CURLSession *)curlSession  {
    if ([_delegate respondsToSelector:@selector(finishedDownloadingAsset:)]) {
        id postprocessedData = [curlSession.assetConnection.assetItem postProcessData:curlSession.assetConnection.connectionData];
        
        CoreAssetManager *assetManager = [[curlSession.assetConnection.assetItem.class parentCamClass] manager];
        
        if([assetManager determineLoginFailure:postprocessedData assetItem:curlSession.assetConnection.assetItem]) {
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
                [_delegate performSelectorOnMainThread:@selector(failedDownloadingAsset:) withObject:@{kCoreAssetWorkerAssetItem:curlSession.assetConnection.assetItem} waitUntilDone:NO];
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
                [_delegate performSelectorOnMainThread:@selector(failedDownloadingAsset:) withObject:@{kCoreAssetWorkerAssetItem:curlSession.assetConnection.assetItem} waitUntilDone:NO];
            }
            else {
                curlSession.assetConnection.connectionData = nil;
                curlSession.request = [curlSession.assetConnection.assetItem createURLRequest];
                //[self performSelector:@selector(rl_curlPerform:) onThread:_thread withObject:curlSession waitUntilDone:NO];
                [self curlStartDownload:curlSession.assetConnection request:curlSession.request];
            }
            
            @synchronized (assetManager.loginCount) {
                NSUInteger count = assetManager.loginCount.unsignedIntegerValue;
                assetManager.loginCount = @(count - 1);
            }
            
            return;
        }
        
        [_delegate performSelectorOnMainThread:@selector(finishedDownloadingAsset:) withObject:@{kCoreAssetWorkerAssetItem:curlSession.assetConnection.assetItem, kCoreAssetWorkerAssetData:curlSession.assetConnection.connectionData, kCoreAssetWorkerAssetPostprocessedData:postprocessedData} waitUntilDone:NO];
    }
}

- (void)initCURL {
    if (!_curl) {
        _curl = curl_easy_init();
        
        // Some settings I recommend you always set:
        curl_easy_setopt(_curl, CURLOPT_HTTPAUTH, CURLAUTH_ANY);	// support basic, digest, and NTLM authentication
        curl_easy_setopt(_curl, CURLOPT_NOSIGNAL, 1L);	// try not to use signals
        curl_easy_setopt(_curl, CURLOPT_USERAGENT, "FinTech-CoreAssetWorker");	// set a default user agent
        
        // Things specific to this app:
        //curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);	// turn on verbose logging; your app doesn't need to do this except when debugging a connection
        curl_easy_setopt(_curl, CURLOPT_DEBUGFUNCTION, CoreAssetWorkerCurlDebugCallback);
        curl_easy_setopt(_curl, CURLOPT_DEBUGDATA, self);
        curl_easy_setopt(_curl, CURLOPT_WRITEFUNCTION, CoreAssetWorkerCurlWriteCallback);
        curl_easy_setopt(_curl, CURLOPT_HEADERFUNCTION, CoreAssetWorkerCurlHeaderCallback);
        
        _curlDownloadCount = @(0);
        _curlDownloadList = [NSMutableArray new];
    }
}

- (void)t_stop {
    @synchronized(self) {
        [_curlDownloadList removeAllObjects];
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
        return _curlDownloadCount.integerValue > 0;
    }
}

- (void)curlCheckNextDownload {
    CoreAssetURLConnection *assetConnection = _curlDownloadList.firstObject;
    
    NSURLRequest *request = [assetConnection.assetItem createURLRequest];
    
    _timeCurrentStart = CACurrentMediaTime();
    _sizeCurrent = 0;
    _bandwith = 0;
    
    [self curlStartDownload:assetConnection request:request];
    
    //TestLog(@"curlCheckNextDownload: asset: '%@' class: '%@'", assetConnection.assetItem.assetName, NSStringFromClass([assetConnection.assetItem class]));
}

- (void)rl_curlPerform:(CURLSession *)curlSession {
    if (_terminate) {
        @synchronized(self) {
            _curlDownloadCount = @(_curlDownloadCount.integerValue - 1);
        }
        return;
    }
    
    //CFTimeInterval startTime = CACurrentMediaTime();
    
    int attempts = 1;
    CURLcode theResult = CURL_LAST;
    CoreAssetManager *assetManager = [[curlSession.assetConnection.assetItem.class parentCamClass] manager];
    
    while(assetManager.networkStatus != CAMNotReachable && (theResult = curl_easy_perform(_curl)) != CURLE_OK && curlSession.assetConnection.assetItem.retryCount) {
        curlSession.assetConnection.assetItem.retryCount--;
        curlSession.assetConnection.connectionData = nil;
        attempts++;
    }
    
    long http_code = 0;
    curl_easy_getinfo(_curl, CURLINFO_RESPONSE_CODE, &http_code);
    
    //CFTimeInterval endTime = CACurrentMediaTime() - startTime;
    
    //curl_slist_free_all(curlSession.headers);
    //curl_easy_cleanup(curl);
    //curl = NULL;
    
     /*double contentLength = 0;
     curl_easy_getinfo(curl, CURLINFO_CONTENT_LENGTH_DOWNLOAD, &contentLength);*/
    
    CoreAssetURLConnection *assetConnection = curlSession.assetConnection;
    
    /*if (http_code == 200 && !assetConnection.connectionData.length) {
     TestLog(@"The CURL misery: %.0f bytes HTTP: %ld", contentLength, http_code);
     }*/
    
    /*if ((endTime < curlSession.request.timeoutInterval && !assetConnection.connectionData) || http_code != 200) {
     TestLog(@"The CURL misery: %.2f s HTTP: %ld", endTime, http_code);
     }*/
    
    @synchronized(self) {
        _curlDownloadCount = @(_curlDownloadCount.integerValue - 1);
        
        if (_terminate) {
            return;
        }
        
        [_curlDownloadList removeObject:assetConnection];
        
        if (!_terminate && _curlDownloadList.count) {
            [self curlCheckNextDownload];
        }
        
        if (!assetConnection.connectionData) {
            assetConnection.connectionData = [NSMutableData new];
        }
        
        if (theResult != CURLE_OK || ![assetConnection validLength] || http_code != 200) {
            TestLog(@"CURL: %@ HTTP_CODE: %d (attempts: %i) Network Status: %d", CURLCodeToNSString(theResult), http_code, attempts, assetManager.networkStatus);
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
            
            [self sendDelegateFinishedDownloadingAsset:curlSession];
        }
    }
}

- (void)curlStartDownload:(CoreAssetURLConnection *)assetConnection request:(NSURLRequest *)request {
    __block CURLSession* curlSession = [CURLSession new];
    curlSession.worker = self;
    curlSession.curl = _curl;
    curlSession.request = request;
    curlSession.assetConnection = assetConnection;
    
    curl_easy_setopt(_curl, CURLOPT_URL, request.URL.absoluteString.UTF8String);
    curl_easy_setopt(_curl, CURLOPT_CONNECTTIMEOUT_MS, (long)request.timeoutInterval * 1000);
    //curl_easy_setopt(_curl, CURLOPT_TIMEOUT_MS, (long)request.timeoutInterval * 1000);
    curl_easy_setopt(_curl, CURLOPT_WRITEDATA, curlSession);	// prevent libcurl from writing the data to stdout
    curl_easy_setopt(_curl, CURLOPT_HEADERDATA, curlSession);
    curl_easy_setopt(_curl, CURLOPT_LOW_SPEED_LIMIT, (long)5);
    curl_easy_setopt(_curl, CURLOPT_LOW_SPEED_TIME, (long)request.timeoutInterval);
    
    NSDictionary *proxySettings = (__bridge_transfer NSDictionary *)CFNetworkCopySystemProxySettings();
    
    // Set up proxies:
    if ([proxySettings objectForKey:(NSString *)kCFNetworkProxiesHTTPEnable] && [[proxySettings objectForKey:(NSString *)kCFNetworkProxiesHTTPEnable] boolValue]) {
        if ([proxySettings objectForKey:(NSString *)kCFNetworkProxiesHTTPProxy]) {
            curlSession.proxyHost = [proxySettings objectForKey:(NSString *)kCFNetworkProxiesHTTPProxy];
            curl_easy_setopt(_curl, CURLOPT_PROXY, curlSession.proxyHost.UTF8String);
        }
        
        if ([proxySettings objectForKey:(NSString *)kCFNetworkProxiesHTTPPort]) {
            curlSession.proxyPort = [proxySettings objectForKey:(NSString *)kCFNetworkProxiesHTTPPort];
            curl_easy_setopt(_curl, CURLOPT_PROXYPORT, curlSession.proxyPort.longValue);
        }
    }
    
    // cookies
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSMutableString *cookieBuild = [NSMutableString new];
    for (NSHTTPCookie *cookie in cookieStorage.cookies) {
        if (cookieBuild.length) {
            [cookieBuild appendString:@"; "];
        }
        
        [cookieBuild appendFormat:@"%@=%@", cookie.name, cookie.value];
    }
    curlSession.cookie = cookieBuild.copy;
    
    curl_easy_setopt(_curl, CURLOPT_COOKIE, curlSession.cookie.UTF8String);
    
    // setup header
    NSMutableArray *headerList = [[NSMutableArray alloc] initWithCapacity:request.allHTTPHeaderFields.count];
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
        NSString *field = [NSString stringWithFormat:@"%@: %@", key, obj];
        [headerList addObject:field];
        curlSession.headers = curl_slist_append(curlSession.headers, field.UTF8String);
    }];
    curlSession.headerList = headerList.copy;
    
    curl_easy_setopt(_curl, CURLOPT_HTTPHEADER, curlSession.headers);
    
    if ([request.HTTPMethod isEqualToString:@"GET"]) {
        curl_easy_setopt(_curl, CURLOPT_UPLOAD, 0L);
        curl_easy_setopt(_curl, CURLOPT_HTTPGET, 1L);
    }
    else if ([request.HTTPMethod isEqualToString:@"POST"]) {
        curl_easy_setopt(_curl, CURLOPT_UPLOAD, 0L);
        curl_easy_setopt(_curl, CURLOPT_HTTPPOST, 1L);
        
        if (request.HTTPBody.length) {
            curl_easy_setopt(_curl, CURLOPT_POSTFIELDSIZE, request.HTTPBody.length);
            curl_easy_setopt(_curl, CURLOPT_POSTFIELDS, request.HTTPBody.bytes);
        }
    }
    
    curl_easy_setopt(_curl, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(_curl, CURLOPT_SSL_VERIFYPEER, 1L);
    
    _curlDownloadCount = @(_curlDownloadCount.integerValue + 1);
    
    //[self performSelector:@selector(rl_curlPerform:) withObject:curlSession afterDelay:0 inModes:@[NSRunLoopCommonModes]];
    [self performSelector:@selector(rl_curlPerform:) onThread:_thread withObject:curlSession waitUntilDone:NO];
}

- (void)rl_downloadAsset:(CoreAssetItemNormal *)asset {
    @synchronized(self) {
        CoreAssetURLConnection *assetConnection = [CoreAssetURLConnection new];
        assetConnection.assetItem = asset;
        
        if (_curlDownloadCount.integerValue > 0) {
            [_curlDownloadList addObject:assetConnection];
            return;
        }
        
        NSURLRequest *request = [asset createURLRequest];
        
        _timeCurrentStart = CACurrentMediaTime();
        _sizeCurrent = 0;
        _bandwith = 0;
        
        [self initCURL];
        [self curlStartDownload:assetConnection request:request];
    }
}

- (void)t_downloadAsset:(CoreAssetItemNormal *)asset {
    CFIndex count = _curlDownloadCount.integerValue;
    
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
