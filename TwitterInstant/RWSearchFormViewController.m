//
//  RWSearchFormViewController.m
//  TwitterInstant
//
//  Created by Colin Eberhardt on 02/12/2013.
//  Copyright (c) 2013 Colin Eberhardt. All rights reserved.
//

#import "RWSearchFormViewController.h"
#import "RWSearchResultsViewController.h"

#import <ReactiveObjC/ReactiveObjC.h>
#import <ReactiveObjC/RACEXTScope.h>

#import <Accounts/Accounts.h>
#import <Social/Social.h>

#import "RWTweet.h"
#import "NSArray+LinqExtensions.h"

typedef NS_ENUM(NSInteger, RWTwitterInstantError) {
    RWTwitterInstantErrorAccessied = 0,
    RWTwitterInstantErrorNoTwitterAccounts,
    RWTwitterInstantErrorInvalidResponse
};

static NSString *const RWTwitterInstantDomain = @"TwitterInstant";

@interface RWSearchFormViewController ()

@property (weak, nonatomic) IBOutlet UITextField *searchText;

@property (strong, nonatomic) RWSearchResultsViewController *resultsViewController;

@property (strong, nonatomic) ACAccountStore *accountStore;
@property (strong, nonatomic) ACAccountType *twitterAccountType;

@end

@implementation RWSearchFormViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title = @"Twitter Instant";
    
    [self styleTextField:self.searchText];
    
    self.resultsViewController = self.splitViewController.viewControllers[1];
    
    @weakify(self)
    [[self.searchText.rac_textSignal
      map:^id _Nullable(NSString * _Nullable value) {
          return [self isValidSearchText:value] ? [UIColor whiteColor] : [UIColor yellowColor];
      }]
     subscribeNext:^(id  _Nullable x) {
         @strongify(self)
         self.searchText.backgroundColor = x;
     }];
    
    // 创建帐号的库 和 twitter帐号的标识
    self.accountStore = [[ACAccountStore alloc] init];
    self.twitterAccountType = [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    
    [[self requestAccessToTwitterSignal] subscribeNext:^(id  _Nullable x) {
        NSLog(@"Access granted");
    } error:^(NSError * _Nullable error) {
        NSLog(@"An error occurred: %@", error);
    }];
    
    // then方法会z一直等待直到信号的completed时间被发送
    [[[[[[[self requestAccessToTwitterSignal] then:^RACSignal * _Nonnull{
        @strongify(self)
        return self.searchText.rac_textSignal;
    }] filter:^BOOL(id  _Nullable value) {
        @strongify(self)
        return [self isValidSearchText:value];
    }] throttle:0.5] //throttle:0.5] 只在时间间隔内美欧收到新的next时间才回发生next时间给i下一节
       flattenMap:^__kindof RACSignal * _Nullable(id  _Nullable value) {
           @strongify(self)
           return [self signalForSearchWithText:value];
       }] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(id  _Nullable x) {
         NSArray *statuses = x[@"statuses"];
         NSArray *tweets = [statuses linq_select:^id(id item) {
             return [RWTweet tweetWithStatus:item];
         }];
         [self.resultsViewController displayTweets:tweets];
     } error:^(NSError * _Nullable error) {
         NSLog(@"An error occurred: %@", error);
     }];
    
}

// 创建请求信号
- (RACSignal *)signalForSearchWithText:(NSString *)text {
    NSError *noAccountsError = [NSError errorWithDomain:RWTwitterInstantDomain code:RWTwitterInstantErrorNoTwitterAccounts userInfo:nil];
    NSError *invalidResponseError = [NSError errorWithDomain:RWTwitterInstantDomain code:RWTwitterInstantErrorInvalidResponse userInfo:nil];
    
    // 创建信号block
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable * _Nullable(id<RACSubscriber>  _Nonnull subscriber) {
        @strongify(self)
        // 创建请求
        SLRequest *request = [self requestForTwitterSearchWithText:text];
        
        // 提供twitter帐号
        NSArray *twitterAccounts = [self.accountStore accountsWithAccountType:self.twitterAccountType];
        if (twitterAccounts.count == 0) {
            [subscriber sendError:noAccountsError];
        } else {
            [request setAccount:[twitterAccounts lastObject]];
        }
        // 发生请求
        [request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
            if (urlResponse.statusCode == 200) {
                // 请求成功，解析响应
                NSDictionary *timeLineData = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingAllowFragments error:nil];
                [subscriber sendNext:timeLineData];
                [subscriber sendCompleted];
            } else {
                // 请求失败
                [subscriber sendError:invalidResponseError];
            }
        }];
        return nil;
    }];
}

// 开始搜索数据
- (SLRequest *)requestForTwitterSearchWithText:(NSString *)text {
    NSURL *url = [NSURL URLWithString:@"https://api.twitter.com/1.1/search/tweets.json"];
    NSDictionary *params = @{
                             @"q" : text,
                             };
    SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeTwitter requestMethod:SLRequestMethodGET URL:url parameters:params];
    return request;
}

// 请求Twitterq权限
- (RACSignal *)requestAccessToTwitterSignal {
    // 1.默认错误
    NSError *accessError = [NSError errorWithDomain:RWTwitterInstantDomain code:RWTwitterInstantErrorAccessied userInfo:nil];
    
    // 2.创建信号
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable * _Nullable(id<RACSubscriber>  _Nonnull subscriber) {
        // 3. 请求twitter帐号
        @strongify(self)
        [self.accountStore requestAccessToAccountsWithType:self.twitterAccountType options:nil completion:^(BOOL granted, NSError *error) {
            if (!granted) {
                [subscriber sendError:accessError];
            } else {
                [subscriber sendNext:nil];
                [subscriber sendCompleted];
            }
        }];
        return nil;
    }];
}

- (BOOL)isValidSearchText:(NSString *)text {
    return text.length > 2;
}

- (void)styleTextField:(UITextField *)textField {
    CALayer *textFieldLayer = textField.layer;
    textFieldLayer.borderColor = [UIColor grayColor].CGColor;
    textFieldLayer.borderWidth = 2.0f;
    textFieldLayer.cornerRadius = 0.0f;
}

@end
