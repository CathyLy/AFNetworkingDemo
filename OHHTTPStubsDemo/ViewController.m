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
    
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    NSURLSessionDataTask *task = [manager GET:@"https://idont.cc" parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSLog(@"%@",responseObject);
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"%@",error);
    }];
    
    NSMutableArray *mArr = [NSMutableArray array];
    NSDictionary *dict = @{@"cathy":@"liu",@"aaa":@"111",@"zzz":@"999"};
   NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"a" ascending:YES selector:@selector(compare:)];
    
    [dict.allKeys sortedArrayUsingDescriptors:@[sortDescriptor]];
//    for (id key in ) {
//        id value = [dict valueForKey:key];
////        mArr addObjectsFromArray:<#(nonnull NSArray *)#>
//    }
    
    NSLog(@"%@",sortDescriptor);
    
}

@end
