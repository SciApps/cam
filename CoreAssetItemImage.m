//
//  CoreAssetItemImage.m
//  CoreAssetManager
//
//  Created by Bálint Róbert on 04/05/15.
//  Copyright (c) 2015 Incepteam All rights reserved.
//

#import <CoreText/CTStringAttributes.h>
#import <UIKit/UIKit.h>
#import "CoreAssetItemImage.h"

@implementation CoreAssetItemErrorImage

+ (instancetype)imageWithImage:(UIImage *)image {
    return [[CoreAssetItemErrorImage alloc] initWithCGImage:image.CGImage];
}

+ (NSDictionary *)attributedFormatForError {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    
    return @{NSForegroundColorAttributeName:[UIColor whiteColor], NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue-Bold" size:44], NSParagraphStyleAttributeName:paragraph};
}

+ (id)imageWithCustomErrorString:(NSString *)errorString maxWidth:(CGFloat)maxWidth {
#ifdef DEBUG
    NSMutableAttributedString* displayName = [NSMutableAttributedString new];
    NSDictionary* errorFormat = [CoreAssetItemErrorImage attributedFormatForError];
    NSString *errorText = [NSString stringWithFormat:@"NO PIC\n%@", errorString];
    [displayName appendAttributedString:[[NSAttributedString alloc] initWithString:errorText attributes:errorFormat]];
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(maxWidth, maxWidth), NO, 1);
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetRGBFillColor(ctx, 64.0 /255, 64.0 / 255.0, 64.0 / 255.0, 1.0);
    
    CGPoint center = CGPointMake(maxWidth / 2, maxWidth / 2); // get the circle centre
    CGFloat radius = 0.9 * center.x; // little scaling needed
    CGFloat startAngle = -((float)M_PI / 2); // 90 degrees
    CGFloat endAngle = ((2 * (float)M_PI) + startAngle);
    CGContextAddArc(ctx, center.x, center.y, radius + 4, startAngle, endAngle, 0); // create an arc the +4 just adds some pixels because of the polygon line thickness
    CGContextFillPath(ctx); // draw
    
    CGSize textSize = [displayName size];
    [displayName drawInRect:CGRectMake(maxWidth*.5-textSize.width*.5, maxWidth*.5-textSize.height*.5, textSize.width, textSize.height)];
    
    UIImage *imageError = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [CoreAssetItemErrorImage imageWithImage:imageError];
#else
    return [NSNull null];
#endif
}

@end

@implementation CoreAssetItemImage

+ (NSUInteger)workerThreads {
    return 4;
}

- (NSString *)fileSystemPath {
    NSString *fsPath = [[CoreAssetItemNormal assetStorageDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"images/%@", super.assetName]];
    return [fsPath stringByAppendingString:@""];
}

- (NSURLRequest *)createURLRequest {
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    
    /*NSURL * baseUrl = [NSURL URLWithString:kBaseUrlStr];
    NSURL * imageAssetEndPointUrl = [baseUrl URLByAppendingPathComponent:kImageAssetEndPointStr];
    NSURL * imageAssetUrl = [imageAssetEndPointUrl URLByAppendingPathComponent:super.assetName];
    
    [request setURL: imageAssetUrl];
    [request setHTTPMethod:@"GET"];*/
    
    return request;
}

- (id)scaleDownImage:(NSData *)imageData {
    const CGFloat maxWidth = [UIScreen mainScreen].bounds.size.width * [UIScreen mainScreen].scale;
    UIImage *imageOriginal;
    
    if (!imageData ||
        !(imageOriginal = [UIImage imageWithData:imageData])) {
        
        return [CoreAssetItemErrorImage imageWithCustomErrorString:self.assetName maxWidth:maxWidth];
    }
    
    CGSize sizeOriginal = imageOriginal.size;
    
    if (sizeOriginal.width <= maxWidth) {
        return imageOriginal;
    }
    
    const CGFloat originalNewRatio = maxWidth / sizeOriginal.width;
    CGSize sizeNew = CGSizeMake(maxWidth, floor(sizeOriginal.height * originalNewRatio));
    
    UIGraphicsBeginImageContextWithOptions(sizeNew, NO, 1);
    [imageOriginal drawInRect:CGRectMake(0, 0, sizeNew.width, sizeNew.height)];
    UIImage *imageNew = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return imageNew;
}

- (id)postProcessData:(NSData *)assetData {
    return [self scaleDownImage:assetData];
}

@end
