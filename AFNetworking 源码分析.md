#### 一.AFNetworking的整体架构
    下面是AFN的整体架构
![image](https://raw.githubusercontent.com/CathyLy/imageForSource/master/AFNetworking.png)
    
    大致分为网络通信模块,网络监听状态模块,网络通信安全策略模块,网络通信信息序列化&反序列化模块等构成
    AFNetworking实际上只是对NSURSession的封装,提供一些API方便我们在iOS开发中发出网络qingqiu
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    [manager GET:@"https://idont.cc" parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSLog(@"%@",responseObject);
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"%@",error);
    }];
    在苹果iOS9中,苹果默认全局HTTPS,如果你要发送不安全的HTTP请求,需要在info.plist中加入如下键值对才能发出不安全的HTTP请求
    AFNetworking默认接收json的响应(因为在iOS平台上的框架,一般不需要text/html),如果想要返回html,需要设置acceptableContentTypes

AFN的调用栈
    
    - [AFHTTPSessionManager initWithBaseURL:]
        - [AFHTTPSessionManager initWithBaseURL: sessionConfiguration:]
            - [AFHTTPSessionManager defaultSessionConfiguration]
                - [NSURLSession sessionWithConfiguration: delegate: delegateQueue:]
                - [AFSecurityPolicy defaultPolicy];//负责身份认证
                - [AFNetworkReachabilityManager sharedManager];//查看网络连接情况
            - [AFHTTPRequestSerializer serializer];//负责序列化请求
            - [AFJSONResponseSerializer serializer];//负责序列化响应

    从上面可以清晰的了解到:
    1.AFHTTPSessionManager继承了AFURLSessionManager
    2.AFURLSessionManager负责生成NSURLSession的对象,管理AFSecurityPolicy和AFNetworkReachabilityManager来保证请求的安全和网络连接情况,
    AFJSONResponseSerializer序列化HTTP的响应.其中请求网络是由NSURLSession来做的,它的内部维护了一个线程池,是基于CFSocket去发送请求和接收数据
    
    3.AFHTTPSessionManager有自己的AFHTTPRequestSerializer和AFJSONResponseSerializer来管理请求和响应的序列化,同时依赖父类提供的接口保证安全,监
    控网络状态实现HTTP请求功能
    
#### 二.AFNetworking的核心类-AFURLSessionManager
    1.负责创建和管理NSURLSession
    2.管理NSURLSessionTask
    3.实现URLSeesionDelegate等协议中的代理方法
    4.使用AFURLSessionManagerTaskDelegate管理进度
    5.使用_AFURLSessionTaskSwizzling调剂方法(替换NSURLSession中的resume和suspend方法,在正常处理原有逻辑的同时,会多发一个通知)
    6.引入AFSecurityPolicy保证请求的安全
    7.引入AFNetworkReachabilityManager监控网络状态
##### 1.负责创建和管理NSURLSession
     - (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    self = [super init];
    if (!self) {
        return nil;
    }

    if (!configuration) {
        configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    }

    self.sessionConfiguration = configuration;

    self.operationQueue = [[NSOperationQueue alloc] init];
    //仅仅是回调代理的并发线程数为1,并不是请求网络的线程数
    //请求网络是由NSURLSession来做的,它的内部维护了一个线程池,用来做网络请求,基于CFSocket去发送请求和接受数据
    self.operationQueue.maxConcurrentOperationCount = 1;
    //代理的继承，实际上NSURLSession去判断了，你实现了哪个方法会去调用，包括子代理的方法！
    self.session = [NSURLSession sessionWithConfiguration:self.sessionConfiguration delegate:self delegateQueue:self.operationQueue];
    //各种响应转码
    self.responseSerializer = [AFJSONResponseSerializer serializer];
    //设置默认的安全策略
    self.securityPolicy = [AFSecurityPolicy defaultPolicy];

    #if !TARGET_OS_WATCH
    self.reachabilityManager = [AFNetworkReachabilityManager sharedManager];
     #endif
    //在AFN中每一个task都有一个对应的AFURLSessionManagerTaskDelegate来做task的delegate事件处理
    //建立映射使用
    //AF对task的代理进行了一个封装,并且将代理转到AF自定义的代理上
    self.mutableTaskDelegatesKeyedByTaskIdentifier = [[NSMutableDictionary alloc] init];

    //确保字典在多线程访问时是安全的
    self.lock = [[NSLock alloc] init];
    self.lock.name = AFURLSessionManagerLockName;

    //置空task关联的delegate
    //异步获取当前session所有未完成的task ?? (outstanding data)
    //this for restoring a session from the background
    [self.session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        for (NSURLSessionDataTask *task in dataTasks) {
            [self addDelegateForDataTask:task uploadProgress:nil downloadProgress:nil completionHandler:nil];
        }

        for (NSURLSessionUploadTask *uploadTask in uploadTasks) {
            [self addDelegateForUploadTask:uploadTask progress:nil completionHandler:nil];
        }

        for (NSURLSessionDownloadTask *downloadTask in downloadTasks) {
            [self addDelegateForDownloadTask:downloadTask progress:nil destination:nil completionHandler:nil];
        }
    }];

    return self;
    }
    
    总结如下在初始化方法
    - 初始化会话配置(NSURLSessionConfiguration),默认是defaultSessionConfiguration
    - 在初始化话(session),并设置会话的代理以及代理队列
    - 初始化管理响应序列化AFJSONResponseSerializer,安全认证AFSecurityPolicy,以及监控网络状态的实例AFNetworkReachabilityManager
    - 初始化保存data task的字典AFNetworkReachabilityManager
                    
#####  2.管理NSURLSessionTask       
    - (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
     {
    return [self dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:completionHandler];
      }

    - (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               uploadProgress:(nullable void (^)(NSProgress *uploadProgress)) uploadProgressBlock
                             downloadProgress:(nullable void (^)(NSProgress *downloadProgress)) downloadProgressBlock
                            completionHandler:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject,  NSError * _Nullable error))completionHandler {
    //sync 想让主线程等,等执行dataTask完才有数据,传值才有意义
    //用串行队列，因为这块是为了防止ios8以下内部的dataTaskWithRequest是并发创建的
    __block NSURLSessionDataTask *dataTask = nil;
    url_session_manager_create_task_safely(^{
        dataTask = [self.session dataTaskWithRequest:request];
    });
     //方法得到一个AFURLSessionManagerTaskDelegate对象,将uploadProgressBlock,downloadProgressBlock,completionHandler传入该对象并在相应事件发生时回调
    [self addDelegateForDataTask:dataTask uploadProgress:uploadProgressBlock downloadProgress:downloadProgressBlock completionHandler:completionHandler];

    return dataTask;
    }
    
    在addDelegateForDataTask方法中调用了setDelegate方法设置代理
    - (void)setDelegate:(AFURLSessionManagerTaskDelegate *)delegate
            forTask:(NSURLSessionTask *)task
    {
    NSParameterAssert(task);
    NSParameterAssert(delegate);

    [self.lock lock];
    
    //将dalegate放入taskIdentifier标记的词典中,唯一对应 AF delegate与task建立映射
    self.mutableTaskDelegatesKeyedByTaskIdentifier[@(task.taskIdentifier)] = delegate;
    //设置task进度的监听
    [delegate setupProgressForTask:task];
    //设置task的Suspend和Resume
    [self addNotificationObserverForTask:task];
    //使用 NSLock 来保证不同线程使用 mutableTaskDelegatesKeyedByTaskIdentifier 时，不会出现线程竞争的问题
    [self.lock unlock];
    }
    
#####  3.实现URLSeesionDelegate等协议中的代理方法
    在manager初始化方法中奖NSURLSession的代理指向self,然后实现这个代理方法,提供更简洁的block接口
    - NSURLSessionDelegate
    - NSURLSessionTaskDelegate
    - NSURLSessionDataDelegate
    - NSURLSessionDownloadDelegate
    
    manager为所有的代理协议都提供了对应的block接口
    - 首先调用setter方法,将block存入属性中
    - 当代理方法调用的时候,如果存在对应的block,会执行block回调
    
    a.NSURLSessionDelegate
     //作者在@property把这些block属性在.m文件中声明,然后复写了set方法,在.h中声明set方法,调用set方法设置bolck的属性,能够很清晰的看到block的各种参数与返回值 ??
      - (void)setSessionDidBecomeInvalidBlock:(void (^)(NSURLSession *session, NSError *error))block {
    self.sessionDidBecomeInvalid = block;
    }
    
    //当前session已经失效时,该代理方法被调用
    //使用finishTasksAndInvalidate 函数会使session失效
    - (void)URLSession:(NSURLSession *)session
    didBecomeInvalidWithError:(NSError *)error
    {
    if (self.sessionDidBecomeInvalid) {
        self.sessionDidBecomeInvalid(session, error);
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDidInvalidateNotification object:session];
    }
  
    - URLSession:didReceiveChallenge:completionHandler:completionHandler  
    下面这个代理方法主要的功能服务器接收客户端请求时->验证客户端->要求客户端接收挑战->生成挑战证书->completionHandler回应服务器的挑战https认证
    
    b.NSURLSessionTaskDelegate
    主要是为task提供进度管理功能,并在task结束的时候回调
    
    - URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:
    这个代理方法主要是被服务器重定向的时候会调用
    
    - URLSession:task:task didReceiveChallenge:completionHandler:completionHandler
    
    - URLSession:task:needNewBodyStream:
    当一个session task需要发送一个新的requst body stream到服务器的时候,调用该方法
    该代理会在下面两种情况调用:
    1.如果task是由uploadTaskWithStreamedRequest创建,提供初始的request body stearm会调用该代理方法
    2.认证挑战或其他可恢复的服务器错误,而导致需要的客户端重新发送一个含有body stream 的reuqest
    
    - URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:
    周期性地通知代理发送到服务器数据的进度
    
    - URLSession:task:didCompleteWithError
    在这个代理方法中会转发给绑定的delegate,并在转移完之后移除代理,task和AFN的delegate
    
    c.NSURLSessionDataDelegate
    - URLSession:dataTask:didReceiveResponse:completionHandler
    data task获取了服务器传回的最初始回复,通过completionHandler这个block传入一个NSURLSessionResponseDisposition
    的变量决定传输任务接下来该做什么,在这个方法里需要处理之前传回来的数据,否则数据会被覆盖
    
    d.NSURLSessionDownloadDelegate
    - URLSession:downloadTask:didFinishDownloadingToURL
      - 下载完成的时候会调用,在这个方法中会调用manager自定义的block拿到文件的存储地址
      - 通过NSFileManager将临时文件移至我们需要的路径
      - 转发代理
      
#####  4.使用AFURLSessionManagerTaskDelegate管理进度
    这个类主要是为task提供进度管理功能,并在task结束的时候回调
    - setupProgressForTask
      - 这个方法主要是设置上传进度或者下载进度状态改变的时候的回调
      - 设置KVO,对task和progress属性进行键值观测
      
    - URLSession:task:didCompleteWithError:
    AF实现的代理,被从URLSession中转过来的,调用completionHandler,发出AFNetworkingTaskDidCompleteNotification通知
    
    - URLSession:dataTask:didReceiveData
    会在收到数据的时候调用
    
    - URLSession:downloadTask:didFinishDownloadingToURL
    会在下载完成的时候调用
    
#####  5.使用_AFURLSessionTaskSwizzling调剂方法
    
    这个类的功能就是替换NSURLSession中的resume和suspend方法,在正常处理原有逻辑的同时,多发送一个通知
    而方法的交换是在+load里面完成


#### 三.AFSecurityPolicy网络通信安全策略模块
    
    AFSecurityPolicy 是ANFetworking 用来保证HTTP请求安全的类,它被AFURLSessionManager持有
    
    - (BOOL)evaluateServerTrust:forDomain
    这个方法来判断当前服务器是否被信任
        NSMutableArray *policies = [NSMutableArray array];
    //验证域名
    if (self.validatesDomainName) {
        // 如果需要验证domain，那么就使用SecPolicyCreateSSL函数创建验证策略，其中第一个参数为true表示验证整个SSL证书链，第二个参数传入domain，用于判断整个证书链上叶子节点表示的那个domain是否和此处传入domain一致
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
        
        /*
         SecPolicyCreateSSL(<#Boolean server#>, <#CFStringRef  _Nullable hostname#>) :
         创建一个验证SSL的策略，两个参数，
         第一个参数true则表示验证整个证书链
         第二个参数传入domain，用于判断整个证书链上叶子节点表示的那个domain是否和此处传入domain一致
         */
    } else {
        // 如果不需要验证domain，就使用默认的BasicX509验证策略
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
        /*
         SecPolicyCreateBasicX509()
         默认的BasicX509验证策略,不验证域名
         */
    }
    // 为serverTrust设置验证策略，即告诉客户端如何验证serverTrust
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);


    if (self.SSLPinningMode == AFSSLPinningModeNone) {
        //如果是AFSSLPinningModeNone，是自签名，直接返回可信任，否则不是自签名的就去系统根证书里去找是否有匹配的证书。
        return self.allowInvalidCertificates || AFServerTrustIsValid(serverTrust);
    } else if (!AFServerTrustIsValid(serverTrust) && !self.allowInvalidCertificates) {
        return NO;
    }

    switch (self.SSLPinningMode) {
        case AFSSLPinningModeNone:
        default:
            return NO;
            //验证证书类型
        case AFSSLPinningModeCertificate: {
            NSMutableArray *pinnedCertificates = [NSMutableArray array];
            //把证书data，用系统api转成 SecCertificateRef 类型的数据,SecCertificateCreateWithData函数对原先的pinnedCertificates做一些处理，保证返回的证书都是DER编码的X.509证书
            for (NSData *certificateData in self.pinnedCertificates) {
                [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
            }
            //锚点证书
            //serverTrust是服务器来的证书
            SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);

            if (!AFServerTrustIsValid(serverTrust)) {
                return NO;
            }

            // obtain the chain after being validated, which *should* contain the pinned certificate in the last position (if it's the Root CA)
            //个方法和我们之前的锚点证书没关系了，是去从我们需要被验证的服务端证书，去拿证书链
            //服务器端的证书链，注意此处返回的证书链顺序是从叶节点到根节点??
            NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
            //reverseObjectEnumerator逆序
            for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
                //如果我们的证书中,有一个和它的证书链中的证书匹配,就返回yes
                if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
                    return YES;
                }
            }
            
            return NO;
        }
        case AFSSLPinningModePublicKey: {
            NSUInteger trustedPublicKeyCount = 0;
            //从serverTrust中取出服务器端传过来的可用证书,并依次得到相应的公钥
            NSArray *publicKeys = AFPublicKeyTrustChainForServerTrust(serverTrust);

            //遍历服务器端的公钥
            for (id trustChainPublicKey in publicKeys) {
                //遍历客户端的公钥
                for (id pinnedPublicKey in self.pinnedPublicKeys) {
                    //判断相同
                    if (AFSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
                        trustedPublicKeyCount += 1;
                    }
                }
            }
            return trustedPublicKeyCount > 0;
        }
    }
    
#### 7.引入AFNetworkReachabilityManager监控网络状态
     AFURLSessionManager 对网络状态的监控是由 AFNetworkReachabilityManager 来负责的，它仅仅是持有一个 AFNetworkReachabilityManager 的对象


    
    

    
    