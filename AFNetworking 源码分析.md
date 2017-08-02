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
                    
    