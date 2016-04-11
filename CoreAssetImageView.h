//
//  CoreAssetImageView.h
//  CoreAssetManager
//
//  Created by mrnuku on 2016. 01. 17..
//  Copyright © 2016. mrnuku. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol CoreAssetImageViewDisplayableDelegate <NSObject>

@optional
- (NSString *)assetNameForUserData:(id)userData;

@end

IB_DESIGNABLE
@interface CoreAssetImageView : UIImageView

+ (Class)parentCamItemClass;

@property (nonatomic, strong) UIImage *emptyImage;
@property (nonatomic, strong) id userData;
@property (nonatomic, strong) NSObject<CoreAssetImageViewDisplayableDelegate> *parentRecord;
@property (nonatomic) IBInspectable BOOL circleShaped;
@property (nonatomic, strong) NSString *assetName;

@end
