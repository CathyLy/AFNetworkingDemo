//
//  ViewController.m
//  OHHTTPStubsDemo
//
//  Created by 刘婷 on 17/2/14.
//  Copyright © 2017年 刘婷. All rights reserved.
//

#import "ViewController.h"
#import <OHHTTPStubs.h>
#import <OHHTTPStubs/OHPathHelpers.h>
#import <AFNetworking.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [OHHTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest * _Nonnull request) {
        return [request.URL.path isEqualToString:@"https://idont.cc"];
    } withStubResponse:^OHHTTPStubsResponse * _Nonnull(NSURLRequest * _Nonnull request) {
        NSString *fisture = OHPathForFile(@"api_test.json", self.class);
        return [OHHTTPStubsResponse responseWithFileAtPath:fisture statusCode:200 headers:@{@"Content-Type":@"application/json"}];
    }];
    
    /*
     1.一般在主线程初始化manager,调用get,post方法请求数据
     2.当调用resume之后,在NSURLSession中对网络进行对并发数据的请求
     3.数据请求完成后,回调回来在我们一开始生成的并发数为1的NSOPerationQueue中,多线程串行回调
     4.数据解析,我们又自己创建并发的多线程,去对数据进行解析???
     */
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
   [manager GET:@"https://idont.cc" parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSLog(@"%@",responseObject);
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"%@",error);
    }];
    
}

@end
