/***********************************************************************************
 *
 * Copyright (c) 2012 Olivier Halligon
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 ***********************************************************************************/

#if ! __has_feature(objc_arc)
#error This file is expected to be compiled with ARC turned ON
#endif

////////////////////////////////////////////////////////////////////////////////
#pragma mark - Imports

#import "OHHTTPStubs.h"

////////////////////////////////////////////////////////////////////////////////
#pragma mark - Types & Constants

@interface OHHTTPStubsProtocol : NSURLProtocol @end

static NSTimeInterval const kSlotTime = 0.25; // Must be >0. We will send a chunk of the data from the stream each 'slotTime' seconds

////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private Interfaces

@interface OHHTTPStubs()
+ (instancetype)sharedInstance;
@property(atomic, copy) NSMutableArray* stubDescriptors;
@property(atomic, assign) BOOL enabledState;
@property(atomic, copy, nullable) void (^onStubActivationBlock)(NSURLRequest*, id<OHHTTPStubsDescriptor>, OHHTTPStubsResponse*);
@property(atomic, copy, nullable) void (^onStubRedirectBlock)(NSURLRequest*, NSURLRequest*, id<OHHTTPStubsDescriptor>, OHHTTPStubsResponse*);
@property(atomic, copy, nullable) void (^afterStubFinishBlock)(NSURLRequest*, id<OHHTTPStubsDescriptor>, OHHTTPStubsResponse*, NSError*);
@end


//OHHTTPStubsDescriptor仅仅作为一个保存信息的类
@interface OHHTTPStubsDescriptor : NSObject <OHHTTPStubsDescriptor>
@property(atomic, copy) OHHTTPStubsTestBlock testBlock;
@property(atomic, copy) OHHTTPStubsResponseBlock responseBlock;
@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark - OHHTTPStubsDescriptor Implementation

@implementation OHHTTPStubsDescriptor

@synthesize name = _name;

+(instancetype)stubDescriptorWithTestBlock:(OHHTTPStubsTestBlock)testBlock
                             responseBlock:(OHHTTPStubsResponseBlock)responseBlock
{
    OHHTTPStubsDescriptor* stub = [OHHTTPStubsDescriptor new];
    stub.testBlock = testBlock;
    stub.responseBlock = responseBlock;
    return stub;
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"<%@ %p : %@>", self.class, self, self.name];
}

@end




////////////////////////////////////////////////////////////////////////////////
#pragma mark - OHHTTPStubs Implementation

@implementation OHHTTPStubs

////////////////////////////////////////////////////////////////////////////////
#pragma mark - Singleton methods

+ (instancetype)sharedInstance
{
    static OHHTTPStubs *sharedInstance = nil;
    
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark - Setup & Teardown

+ (void)initialize
{
    if (self == [OHHTTPStubs class])
    {
        [self _setEnable:YES];
    }
}
- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _stubDescriptors = [NSMutableArray array];
        _enabledState = YES; // assume initialize has already been run
    }
    return self;
}

- (void)dealloc
{
    [self.class _setEnable:NO];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public class methods

#pragma mark > Adding & Removing stubs

+(id<OHHTTPStubsDescriptor>)stubRequestsPassingTest:(OHHTTPStubsTestBlock)testBlock
                                   withStubResponse:(OHHTTPStubsResponseBlock)responseBlock
{
    //OHHTTPStubs遵循代理的模式,对stub添加到stubDescriptors数组中
    OHHTTPStubsDescriptor* stub = [OHHTTPStubsDescriptor stubDescriptorWithTestBlock:testBlock
                                                                       responseBlock:responseBlock];
    [OHHTTPStubs.sharedInstance addStub:stub];
    return stub;
}

+(BOOL)removeStub:(id<OHHTTPStubsDescriptor>)stubDesc
{
    return [OHHTTPStubs.sharedInstance removeStub:stubDesc];
}

+(void)removeAllStubs
{
    [OHHTTPStubs.sharedInstance removeAllStubs];
}

#pragma mark > Disabling & Re-Enabling stubs

+(void)_setEnable:(BOOL)enable
{
    if (enable)
    {
        //在每一个HTTP请求开始,URL 加载系统创建一个合适的 NSURLProtocol 对象处理对应的 URL 请求
        //注册协议类 使用我们创建的协议对象对该请求进行处理
        [NSURLProtocol registerClass:OHHTTPStubsProtocol.class];
    }
    else
    {
        [NSURLProtocol unregisterClass:OHHTTPStubsProtocol.class];
    }
}

+(void)setEnabled:(BOOL)enabled
{
    [OHHTTPStubs.sharedInstance setEnabled:enabled];
}

+(BOOL)isEnabled
{
    return OHHTTPStubs.sharedInstance.isEnabled;
}

#if defined(__IPHONE_7_0) || defined(__MAC_10_9)
+ (void)setEnabled:(BOOL)enable forSessionConfiguration:(NSURLSessionConfiguration*)sessionConfig
{
    // Runtime check to make sure the API is available on this version
    if (   [sessionConfig respondsToSelector:@selector(protocolClasses)]
        && [sessionConfig respondsToSelector:@selector(setProtocolClasses:)])
    {
        NSMutableArray * urlProtocolClasses = [NSMutableArray arrayWithArray:sessionConfig.protocolClasses];
        Class protoCls = OHHTTPStubsProtocol.class;
        if (enable && ![urlProtocolClasses containsObject:protoCls])
        {
            [urlProtocolClasses insertObject:protoCls atIndex:0];
        }
        else if (!enable && [urlProtocolClasses containsObject:protoCls])
        {
            [urlProtocolClasses removeObject:protoCls];
        }
        sessionConfig.protocolClasses = urlProtocolClasses;
    }
    else
    {
        NSLog(@"[OHHTTPStubs] %@ is only available when running on iOS7+/OSX9+. "
              @"Use conditions like 'if ([NSURLSessionConfiguration class])' to only call "
              @"this method if the user is running iOS7+/OSX9+.", NSStringFromSelector(_cmd));
    }
}

+ (BOOL)isEnabledForSessionConfiguration:(NSURLSessionConfiguration *)sessionConfig
{
    // Runtime check to make sure the API is available on this version
    if (   [sessionConfig respondsToSelector:@selector(protocolClasses)]
        && [sessionConfig respondsToSelector:@selector(setProtocolClasses:)])
    {
        NSMutableArray * urlProtocolClasses = [NSMutableArray arrayWithArray:sessionConfig.protocolClasses];
        Class protoCls = OHHTTPStubsProtocol.class;
        return [urlProtocolClasses containsObject:protoCls];
    }
    else
    {
        NSLog(@"[OHHTTPStubs] %@ is only available when running on iOS7+/OSX9+. "
              @"Use conditions like 'if ([NSURLSessionConfiguration class])' to only call "
              @"this method if the user is running iOS7+/OSX9+.", NSStringFromSelector(_cmd));
        return NO;
    }
}
#endif

#pragma mark > Debug Methods

+(NSArray*)allStubs
{
    return [OHHTTPStubs.sharedInstance stubDescriptors];
}

+(void)onStubActivation:( nullable void(^)(NSURLRequest* request, id<OHHTTPStubsDescriptor> stub, OHHTTPStubsResponse* responseStub) )block
{
    [OHHTTPStubs.sharedInstance setOnStubActivationBlock:block];
}

+(void)onStubRedirectResponse:( nullable void(^)(NSURLRequest* request, NSURLRequest* redirectRequest, id<OHHTTPStubsDescriptor> stub, OHHTTPStubsResponse* responseStub) )block
{
    [OHHTTPStubs.sharedInstance setOnStubRedirectBlock:block];
}

+(void)afterStubFinish:( nullable void(^)(NSURLRequest* request, id<OHHTTPStubsDescriptor> stub, OHHTTPStubsResponse* responseStub, NSError* error) )block
{
    [OHHTTPStubs.sharedInstance setAfterStubFinishBlock:block];
}



////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private instance methods

-(BOOL)isEnabled
{
    BOOL enabled = NO;
    @synchronized(self)
    {
        enabled = _enabledState;
    }
    return enabled;
}

-(void)setEnabled:(BOOL)enable
{
    @synchronized(self)
    {
        _enabledState = enable;
        [self.class _setEnable:_enabledState];
    }
}

//以下几个方法用于管理持有的HTTP stub
-(void)addStub:(OHHTTPStubsDescriptor*)stubDesc
{
    @synchronized(_stubDescriptors)
    {
        [_stubDescriptors addObject:stubDesc];
    }
}

-(BOOL)removeStub:(id<OHHTTPStubsDescriptor>)stubDesc
{
    BOOL handlerFound = NO;
    @synchronized(_stubDescriptors)
    {
        handlerFound = [_stubDescriptors containsObject:stubDesc];
        [_stubDescriptors removeObject:stubDesc];
    }
    return handlerFound;
}

-(void)removeAllStubs
{
    @synchronized(_stubDescriptors)
    {
        [_stubDescriptors removeAllObjects];
    }
}

//设置相应事件发生时的回调
- (OHHTTPStubsDescriptor*)firstStubPassingTestForRequest:(NSURLRequest*)request
{
    OHHTTPStubsDescriptor* foundStub = nil;
    @synchronized(_stubDescriptors)
    {
        //遍历自己持有的全部stub,通过testBlock返回一个符合条件的stub
        for(OHHTTPStubsDescriptor* stub in _stubDescriptors.reverseObjectEnumerator)
        {
            if (stub.testBlock(request))
            {
                foundStub = stub;
                break;
            }
        }
    }
    return foundStub;
}

@end










////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private Protocol Class

@interface OHHTTPStubsProtocol()
@property(assign) BOOL stopped;
@property(strong) OHHTTPStubsDescriptor* stub;
@property(assign) CFRunLoopRef clientRunLoop;
- (void)executeOnClientRunLoopAfterDelay:(NSTimeInterval)delayInSeconds block:(dispatch_block_t)block;
@end

@implementation OHHTTPStubsProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    return ([OHHTTPStubs.sharedInstance firstStubPassingTestForRequest:request] != nil);
}

- (id)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)response client:(id<NSURLProtocolClient>)client
{
    // Make super sure that we never use a cached response.
    OHHTTPStubsProtocol* proto = [super initWithRequest:request cachedResponse:nil client:client];
    proto.stub = [OHHTTPStubs.sharedInstance firstStubPassingTestForRequest:request];
    return proto;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
	return request;
}

- (NSCachedURLResponse *)cachedResponse
{
	return nil;
}

- (void)startLoading
{
    self.clientRunLoop = CFRunLoopGetCurrent();
    NSURLRequest* request = self.request;
    id<NSURLProtocolClient> client = self.client;
    
    if (!self.stub)
    {
        NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  @"It seems like the stub has been removed BEFORE the response had time to be sent.",
                                  NSLocalizedFailureReasonErrorKey,
                                  @"For more info, see https://github.com/AliSoftware/OHHTTPStubs/wiki/OHHTTPStubs-and-asynchronous-tests",
                                  NSLocalizedRecoverySuggestionErrorKey,
                                  request.URL, // Stop right here if request.URL is nil
                                  NSURLErrorFailingURLErrorKey,
                                  nil];
        NSError* error = [NSError errorWithDomain:@"OHHTTPStubs" code:500 userInfo:userInfo];
        [client URLProtocol:self didFailWithError:error];
        if (OHHTTPStubs.sharedInstance.afterStubFinishBlock)
        {
            OHHTTPStubs.sharedInstance.afterStubFinishBlock(request, self.stub, nil, error);
        }
        return;
    }
    
    OHHTTPStubsResponse* responseStub = self.stub.responseBlock(request);
    
    
    //onStubActivationBlock stub被激活的时调用
    if (OHHTTPStubs.sharedInstance.onStubActivationBlock)
    {
        OHHTTPStubs.sharedInstance.onStubActivationBlock(request, self.stub, responseStub);
    }
    
    if (responseStub.error == nil)
    {
        NSHTTPURLResponse* urlResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                                     statusCode:responseStub.statusCode
                                                                    HTTPVersion:@"HTTP/1.1"
                                                                   headerFields:responseStub.httpHeaders];
        //如果响应没有遇到任何问题就会进入Cookies,重定向,发送响应和模拟数据流的过程
        
        //1. Cookies handling
        if (request.HTTPShouldHandleCookies && request.URL)
        {
            NSArray* cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:responseStub.httpHeaders forURL:request.URL];
            if (cookies)
            {
                //NSHTTPCookieStorage ??
                [NSHTTPCookieStorage.sharedHTTPCookieStorage setCookies:cookies forURL:request.URL mainDocumentURL:request.mainDocumentURL];
            }
        }
        
        //2.处理重定向问题,调用onStubRedirectBlock进行需要的回调
        NSString* redirectLocation = (responseStub.httpHeaders)[@"Location"];
        NSURL* redirectLocationURL;
        if (redirectLocation)
        {
            redirectLocationURL = [NSURL URLWithString:redirectLocation];
        }
        else
        {
            redirectLocationURL = nil;
        }
        
        //根据stub中储存的responeTime 来模拟响应的一个延迟时间
        [self executeOnClientRunLoopAfterDelay:responseStub.requestTime block:^{
            if (!self.stopped)
            {
                // Notify if a redirection occurred
                if (((responseStub.statusCode > 300) && (responseStub.statusCode < 400)) && redirectLocationURL)
                {
                    NSURLRequest* redirectRequest = [NSURLRequest requestWithURL:redirectLocationURL];
                    [client URLProtocol:self wasRedirectedToRequest:redirectRequest redirectResponse:urlResponse];
                    if (OHHTTPStubs.sharedInstance.onStubRedirectBlock)
                    {
                        OHHTTPStubs.sharedInstance.onStubRedirectBlock(request, redirectRequest, self.stub, responseStub);
                    }
                }
                
                // Send the response (even for redirections)
                [client URLProtocol:self didReceiveResponse:urlResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                if(responseStub.inputStream.streamStatus == NSStreamStatusNotOpen)
                {
                    [responseStub.inputStream open];
                }
                
                //模拟数据以data的形式分块发送回client的过程,最后调用afterStubFinishBlock
                [self streamDataForClient:client
                         withStubResponse:responseStub
                               completion:^(NSError * error)
                 {
                     [responseStub.inputStream close];
                     NSError *blockError = nil;
                     if (error==nil)
                     {
                         [client URLProtocolDidFinishLoading:self];
                     }
                     else
                     {
                         [client URLProtocol:self didFailWithError:responseStub.error];
                         blockError = responseStub.error;
                     }
                     if (OHHTTPStubs.sharedInstance.afterStubFinishBlock)
                     {
                         OHHTTPStubs.sharedInstance.afterStubFinishBlock(request, self.stub, responseStub, blockError);
                     }
                 }];
            }
        }];
    } else {
        
        //如果在responseStub发生了错误,也会进行类似延迟的操作后并调用block
        // Send the canned error
        [self executeOnClientRunLoopAfterDelay:responseStub.responseTime block:^{
            if (!self.stopped)
            {
                [client URLProtocol:self didFailWithError:responseStub.error];
                if (OHHTTPStubs.sharedInstance.afterStubFinishBlock)
                {
                    OHHTTPStubs.sharedInstance.afterStubFinishBlock(request, self.stub, responseStub, responseStub.error);
                }
            }
        }];
    }
}

- (void)stopLoading
{
    self.stopped = YES;
}

//私有的结构体,包含了发送数据流的信息
typedef struct {
    NSTimeInterval slotTime; //两次发送NSData的数据的时间间隔
    double chunkSizePerSlot; //每块数据流的大小
    double cumulativeChunkSize; //已发送数据流的大小
} OHHTTPStubsStreamTimingInfo;

- (void)streamDataForClient:(id<NSURLProtocolClient>)client
           withStubResponse:(OHHTTPStubsResponse*)stubResponse
                 completion:(void(^)(NSError * error))completion
{
    if (!self.stopped)
    {
        if ((stubResponse.dataSize>0) && stubResponse.inputStream.hasBytesAvailable)
        {
            // Compute timing data once and for all for this stub
            
            OHHTTPStubsStreamTimingInfo timingInfo = {
                .slotTime = kSlotTime, // Must be >0. We will send a chunk of data from the stream each 'slotTime' seconds
                .cumulativeChunkSize = 0
            };
            
            if(stubResponse.responseTime < 0)
            {
                // Bytes send each 'slotTime' seconds = Speed in KB/s * 1000 * slotTime in seconds
                timingInfo.chunkSizePerSlot = (fabs(stubResponse.responseTime) * 1000) * timingInfo.slotTime;
            }
            else if (stubResponse.responseTime < kSlotTime) // includes case when responseTime == 0
            {
                // We want to send the whole data quicker than the slotTime, so send it all in one chunk.
                timingInfo.chunkSizePerSlot = stubResponse.dataSize;
                timingInfo.slotTime = stubResponse.responseTime;
            }
            else
            {
                // Bytes send each 'slotTime' seconds = (Whole size in bytes / response time) * slotTime = speed in bps * slotTime in seconds
                timingInfo.chunkSizePerSlot = ((stubResponse.dataSize/stubResponse.responseTime) * timingInfo.slotTime);
            }
            
            //将生成的OHHTTPStubsStreamTimingInfo传入下一个实例方法
            [self streamDataForClient:client
                           fromStream:stubResponse.inputStream
                           timingInfo:timingInfo
                           completion:completion];
        }
        else
        {
            [self executeOnClientRunLoopAfterDelay:stubResponse.responseTime block:^{
                if (completion && !self.stopped)
                {
                    completion(nil);
                }
            }];
        }
    }
}

- (void) streamDataForClient:(id<NSURLProtocolClient>)client
                  fromStream:(NSInputStream*)inputStream
                  timingInfo:(OHHTTPStubsStreamTimingInfo)timingInfo
                  completion:(void(^)(NSError * error))completion
{
    NSParameterAssert(timingInfo.chunkSizePerSlot > 0);
    
    if (inputStream.hasBytesAvailable && (!self.stopped))
    {
        // This is needed in case we computed a non-integer chunkSizePerSlot, to avoid cumulative errors
        
        
        double cumulativeChunkSizeAfterRead = timingInfo.cumulativeChunkSize + timingInfo.chunkSizePerSlot;
        //计算chunkSizeToRead的长度
        NSUInteger chunkSizeToRead = floor(cumulativeChunkSizeAfterRead) - floor(timingInfo.cumulativeChunkSize);
        timingInfo.cumulativeChunkSize = cumulativeChunkSizeAfterRead;
        
        if (chunkSizeToRead == 0)
        {
            // Nothing to read at this pass, but probably later
            //模拟数据传输的延迟
            [self executeOnClientRunLoopAfterDelay:timingInfo.slotTime block:^{
                [self streamDataForClient:client fromStream:inputStream
                               timingInfo:timingInfo completion:completion];
            }];
        } else {
            uint8_t* buffer = (uint8_t*)malloc(sizeof(uint8_t)*chunkSizeToRead);
            NSInteger bytesRead = [inputStream read:buffer maxLength:chunkSizeToRead];
            if (bytesRead > 0)
            {
                NSData * data = [NSData dataWithBytes:buffer length:bytesRead];
                // Wait for 'slotTime' seconds before sending the chunk.
                // If bytesRead < chunkSizePerSlot (because we are near the EOF), adjust slotTime proportionally to the bytes remaining
                [self executeOnClientRunLoopAfterDelay:((double)bytesRead / (double)chunkSizeToRead) * timingInfo.slotTime block:^{
                    
                    //代理方法将数据传回给client
                    [client URLProtocol:self didLoadData:data];
                    [self streamDataForClient:client fromStream:inputStream
                                   timingInfo:timingInfo completion:completion];
                }];
            }
            else
            {
                if (completion)
                {
                    // Note: We may also arrive here with no error if we were just at the end of the stream (EOF)
                    // In that case, hasBytesAvailable did return YES (because at the limit of OEF) but nothing were read (because EOF)
                    // But then in that case inputStream.streamError will be nil so that's cool, we won't return an error anyway
                    completion(inputStream.streamError);
                }
            }
            free(buffer);
        }
    }
    else
    {
        if (completion)
        {
            completion(nil);
        }
    }
}

/////////////////////////////////////////////
// Delayed execution utility methods
/////////////////////////////////////////////

- (void)executeOnClientRunLoopAfterDelay:(NSTimeInterval)delayInSeconds block:(dispatch_block_t)block
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CFRunLoopPerformBlock(self.clientRunLoop, kCFRunLoopDefaultMode, block);
        CFRunLoopWakeUp(self.clientRunLoop);
    });
}

@end
