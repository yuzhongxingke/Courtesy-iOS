//
//  CourtesyCardManager.m
//  Courtesy
//
//  Created by Zheng on 3/15/16.
//  Copyright © 2016 82Flex. All rights reserved.
//

#import "AppDelegate.h"
#import "AppStorage.h"
#import "FCFileManager.h"
#import "CourtesyCardManager.h"
#import "CourtesyCardComposeViewController.h"
#import "CourtesyPortraitViewController.h"
#import "CourtesyLoginRegisterViewController.h"
#import "CourtesyCardPublishQueue.h"
#import "CourtesyCardDeleteRequestModel.h"

#define kCourtesyCardDraftListKey @"kCourtesyCardListKey"

@interface CourtesyCardManager () <CourtesyCardComposeDelegate, CourtesyCardDeleteRequestDelegate>

@end

@implementation CourtesyCardManager

#pragma mark - 存储

- (AppStorage *)appStorage {
    return [AppStorage sharedInstance];
}

#pragma mark - 初始化

+ (id)sharedManager {
    static CourtesyCardManager *sharedManager = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sharedManager = [[self alloc] init];
    });
    
    return sharedManager;
}

- (instancetype)init {
    if (self = [super init]) {
        [self reloadCards];
    }
    return self;
}

- (void)clearCards {
    self.cardDraftTokenArray = [[NSMutableArray alloc] init];
    self.cardDraftArray = [[NSMutableArray alloc] init];
}

- (void)reloadCards {
    // Load Draft Cards List From Database
    id list_obj = [self.appStorage objectForKey:kCourtesyCardDraftListKey];
    BOOL shouldSync = NO;
    NSMutableArray *tokensShouldBeRemoved = [NSMutableArray new];
    if (list_obj && [list_obj isKindOfClass:[NSMutableArray class]]) {
        self.cardDraftTokenArray = list_obj;
    } else {
        self.cardDraftTokenArray = [[NSMutableArray alloc] init];
    }
    self.cardDraftArray = [[NSMutableArray alloc] init];
    for (NSString *token in self.cardDraftTokenArray) {
        CourtesyCardModel *card = [[CourtesyCardModel alloc] initWithCardToken:token];
        if (!card) {
            shouldSync = YES;
            [tokensShouldBeRemoved addObject:token];
            continue;
        }
        if (
            (card.author.user_id == kAccount.user_id)
            )
        {
            // 如果是当前用户编写的卡片
            card.author = kAccount;
            card.delegate = self;
            [self.cardDraftArray addObject:card];
        } else if (card.read_by && card.read_by.user_id == kAccount.user_id) {
            // 或者是当前用户接收到的卡片
            card.read_by = kAccount;
            card.delegate = self;
            [self.cardDraftArray addObject:card];
        }
    }
    if (shouldSync) { // 需要同步卡片列表数组，因为卡片不存在了
        for (NSString *invalid_token in tokensShouldBeRemoved) {
            [self.cardDraftTokenArray removeObject:invalid_token];
        }
        [self.appStorage setObject:self.cardDraftTokenArray forKey:kCourtesyCardDraftListKey];
    }
}

#pragma mark - 生成新卡片

- (CourtesyCardModel *)newCard {
    // 初始化卡片
    CourtesyCardModel *card = [CourtesyCardModel new];
    card.delegate = self;
    card.is_editable = YES;
    card.is_banned = ![sharedSettings switchAutoPublic];
    card.view_count = 0;
    card.created_at = [[NSDate date] timeIntervalSince1970];
    card.modified_at = [[NSDate date] timeIntervalSince1970];
    card.first_read_at = 0;
    card.token = [[NSUUID UUID] UUIDString];
    card.edited_count = 0;
    card.stars = 0;
    card.author = kAccount;
    card.read_by = nil;
    
    card.local_template = [CourtesyCardDataModel new];
    // 初始化卡片内容
    card.local_template.content = @"说点什么吧……";
    card.local_template.attachments = nil;
    card.local_template.styleID = kCourtesyCardStyleDefault;
    card.local_template.fontType = [sharedSettings preferredFontType];
    card.local_template.fontSize = [sharedSettings preferredFontSize];
    card.local_template.shouldAutoPlayAudio = NO;
    card.local_template.alignmentType = NSTextAlignmentLeft;
    card.local_template.card_token = card.token;
    
    card.isNewCard = YES;
    card.hasPublished = NO;
    return card;
}

#pragma mark - 卡片编辑与查看控制

- (CourtesyCardModel *)composeNewCardWithViewController:(UIViewController *)controller {
    if (![sharedSettings hasLogin]) { // 未登录
        CourtesyLoginRegisterViewController *vc = [CourtesyLoginRegisterViewController new];
        CourtesyPortraitViewController *navc = [[CourtesyPortraitViewController alloc] initWithRootViewController:vc];
        [controller presentViewController:navc animated:YES completion:nil];
        return nil;
    }
    CourtesyCardModel *newCard = [self newCard];
    CourtesyCardComposeViewController *vc = [[CourtesyCardComposeViewController alloc] initWithCard:newCard];
    vc.delegate = self;
    [controller presentViewController:vc animated:YES completion:nil];
    return newCard;
}

- (void)editCard:(CourtesyCardModel *)card withViewController:(UIViewController *)controller {
    if ([card isCardCached]) {
        // 卡片已缓存
        CourtesyCardComposeViewController *vc = [[CourtesyCardComposeViewController alloc] initWithCard:card];
        vc.delegate = self;
        [controller presentViewController:vc animated:YES completion:nil];
    } else {
        // 卡片未缓存或未全部缓存
        // 发起缓存异步请求
    }
}

#pragma mark - 3D Touch

- (UIViewController *)prepareCard:(CourtesyCardModel *)card withViewController:(UIViewController *)controller {
    if ([card isCardCached]) {
        // 卡片已缓存，可以载入预览
        CourtesyCardComposeViewController *vc = [[CourtesyCardComposeViewController alloc] initWithCard:card];
        vc.previewContext = YES;
        vc.delegate = self;
        return vc;
    }
    // 卡片未缓存，无法预览
    return nil;
}

- (void)commitCardComposeViewController:(UIViewController *)viewController withViewController:(UIViewController *)controller {
    CourtesyCardComposeViewController *vc = (CourtesyCardComposeViewController *)viewController;
    vc.previewContext = NO;
    [controller presentViewController:vc animated:YES completion:nil];
}

#pragma mark - 管理卡片

- (void)restoreCardInDraft:(CourtesyCardModel *)card {
    if (card.hasPublished) {
        if (card.is_banned) {
            dispatch_async_on_main_queue(^{
                [JDStatusBarNotification showWithStatus:[NSString stringWithFormat:@"正在公开卡片 %@……", card.local_template.mainTitle]
                                           dismissAfter:kStatusBarNotificationTime
                                              styleName:JDStatusBarStyleDefault];
                [JDStatusBarNotification showActivityIndicator:YES
                                                indicatorStyle:UIActivityIndicatorViewStyleGray];
            });
            
            __block CourtesyCardDeleteRequestModel *restoreRequest = [[CourtesyCardDeleteRequestModel alloc] initWithDelegate:self];
            restoreRequest.token = card.token;
            restoreRequest.card = card;
            restoreRequest.toBan = NO;
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                [restoreRequest sendRequest];
            });
        }
    }
}

- (void)deleteCardInDraft:(CourtesyCardModel *)card {
    if (card.author.user_id == kAccount.user_id) {
        if (card.hasPublished) {
            if (card.is_banned == NO) {
                dispatch_async_on_main_queue(^{
                    [JDStatusBarNotification showWithStatus:[NSString stringWithFormat:@"正在隐藏卡片 %@……", card.local_template.mainTitle]
                                               dismissAfter:kStatusBarNotificationTime
                                                  styleName:JDStatusBarStyleDefault];
                    [JDStatusBarNotification showActivityIndicator:YES
                                                    indicatorStyle:UIActivityIndicatorViewStyleGray];
                });
                
                __block CourtesyCardDeleteRequestModel *deleteRequest = [[CourtesyCardDeleteRequestModel alloc] initWithDelegate:self];
                deleteRequest.token = card.token;
                deleteRequest.card = card;
                deleteRequest.toBan = YES;
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    [deleteRequest sendRequest];
                });
                return;
            }
        }
    }
    [card deleteInLocalDatabase];
    [self.cardDraftTokenArray removeObject:card.token];
    [self.cardDraftArray removeObject:card];
    [self.appStorage setObject:self.cardDraftTokenArray forKey:kCourtesyCardDraftListKey];
}

- (void)exchangeCardAtIndex:(NSInteger)sourceRow withCardAtIndex:(NSInteger)destinationRow {
    [self.cardDraftArray exchangeObjectAtIndex:sourceRow withObjectAtIndex:destinationRow];
    [self.cardDraftTokenArray exchangeObjectAtIndex:sourceRow withObjectAtIndex:destinationRow];
    [self.appStorage setObject:self.cardDraftTokenArray forKey:kCourtesyCardDraftListKey];
}

#pragma mark - CourtesyCardComposeDelegate

- (void)backToAlbumViewController {
    [[[AppDelegate globalDelegate] drawerViewController] setCenterViewController:[[AppDelegate globalDelegate] albumViewController]];
}

- (void)cardComposeViewDidFinishEditing:(nonnull CourtesyCardComposeViewController *)controller {
    if (controller.card) {
        [controller.card saveToLocalDatabaseShouldPublish:YES andNotify:YES];
    }
    [self backToAlbumViewController];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)cardComposeViewWillBeginLoading:(nonnull CourtesyCardComposeViewController *)controller {

}

- (void)cardComposeViewDidFinishLoading:(nonnull CourtesyCardComposeViewController *)controller {

}

- (void)cardComposeViewDidCancelEditing:(CourtesyCardComposeViewController *)controller shouldSaveToDraftBox:(BOOL)save {
    if (save && controller.card) {
        dispatch_async_on_main_queue(^{
            [JDStatusBarNotification showWithStatus:@"正在保存卡片……"
                                          styleName:JDStatusBarStyleDefault];
            [JDStatusBarNotification showActivityIndicator:YES
                                            indicatorStyle:UIActivityIndicatorViewStyleGray];
        });
        [controller.card saveToLocalDatabaseShouldPublish:NO andNotify:YES];
    }
    [self backToAlbumViewController];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - CourtesyCardDelegate

- (void)cardDidFinishLoading:(nonnull CourtesyCardModel *)card {

}

- (void)cardDidFailedLoading:(CourtesyCardModel *)card withError:(NSError *)error {
    
}

- (void)cardDidFinishSaving:(nonnull CourtesyCardModel *)card isNewRecord:(BOOL)newRecord willPublish:(BOOL)willPublish andNotify:(BOOL)notify {
    BOOL newToken = YES;
    for (NSString *token in self.cardDraftTokenArray) {
        if ([token isEqualToString:card.token]) {
            newToken = NO;
        }
    }
    if (newToken) { // 添加记录则将元素加入数组并写入数据库
        [self.cardDraftTokenArray insertObject:card.token atIndex:0];
        [self.cardDraftArray insertObject:card atIndex:0];
    }
    [self.appStorage setObject:self.cardDraftTokenArray forKey:kCourtesyCardDraftListKey];
    if (willPublish == NO) {
        if (notify) {
            dispatch_async_on_main_queue(^{
                [JDStatusBarNotification showWithStatus:@"卡片已保存"
                                           dismissAfter:kStatusBarNotificationTime
                                              styleName:JDStatusBarStyleSuccess];
            });
        }
    } else {
        [[CourtesyCardPublishQueue sharedQueue] addCardPublishTask:card];
    }
}

- (void)cardDidFailedSaving:(nonnull CourtesyCardModel *)card withError:(NSError *)error {
    dispatch_async_on_main_queue(^{
        [JDStatusBarNotification showWithStatus:[NSString stringWithFormat:@"卡片保存失败 - %@", [error localizedDescription]]
                                   dismissAfter:kStatusBarNotificationTime
                                      styleName:JDStatusBarStyleError];
    });
}

#pragma mark - CourtesyCardDeleteRequestDelegate

- (void)cardDeleteRequestSucceed:(CourtesyCardDeleteRequestModel *)sender {
    if (sender.toBan) {
        CourtesyCardModel *card = sender.card;
        dispatch_async_on_main_queue(^{
            [JDStatusBarNotification showWithStatus:[NSString stringWithFormat:@"卡片 %@ 已经隐藏", card.local_template.mainTitle]
                                       dismissAfter:kStatusBarNotificationTime
                                          styleName:JDStatusBarStyleSuccess];
        });
        card.is_banned = YES;
        [card saveToLocalDatabaseShouldPublish:NO andNotify:NO];
        [[NSNotificationCenter defaultCenter] postNotificationName:kCourtesyCardStatusUpdated object:card];
    } else {
        CourtesyCardModel *card = sender.card;
        dispatch_async_on_main_queue(^{
            [JDStatusBarNotification showWithStatus:[NSString stringWithFormat:@"卡片 %@ 已经公开", card.local_template.mainTitle]
                                       dismissAfter:kStatusBarNotificationTime
                                          styleName:JDStatusBarStyleSuccess];
        });
        card.is_banned = NO;
        [card saveToLocalDatabaseShouldPublish:NO andNotify:NO];
        [[NSNotificationCenter defaultCenter] postNotificationName:kCourtesyCardStatusUpdated object:card];
    }
}

- (void)cardDeleteRequestFailed:(CourtesyCardDeleteRequestModel *)sender
                      withError:(NSError *)error {
    if (sender.toBan) {
        CourtesyCardModel *card = sender.card;
        dispatch_async_on_main_queue(^{
            [JDStatusBarNotification showWithStatus:[NSString stringWithFormat:@"卡片 %@ 隐藏失败 - %@", card.local_template.mainTitle, [error localizedDescription]]
                                       dismissAfter:kStatusBarNotificationTime
                                          styleName:JDStatusBarStyleError];
        });
    } else {
        CourtesyCardModel *card = sender.card;
        dispatch_async_on_main_queue(^{
            [JDStatusBarNotification showWithStatus:[NSString stringWithFormat:@"卡片 %@ 公开失败 - %@", card.local_template.mainTitle, [error localizedDescription]]
                                       dismissAfter:kStatusBarNotificationTime
                                          styleName:JDStatusBarStyleError];
        });
    }
}

@end
