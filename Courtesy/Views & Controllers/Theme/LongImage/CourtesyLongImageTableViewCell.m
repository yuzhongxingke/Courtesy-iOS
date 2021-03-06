//
//  CourtesyLongImageTableViewCell.m
//  Courtesy
//
//  Created by Zheng on 5/3/16.
//  Copyright © 2016 82Flex. All rights reserved.
//

#import "CourtesyLongImageTableViewCell.h"
#import "POP.h"

@interface CourtesyLongImageTableViewCell ()
@property (weak, nonatomic) IBOutlet UIImageView *previewImageView;
@property (weak, nonatomic) IBOutlet UIImageView *maskImageView;

@end

@implementation CourtesyLongImageTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    
    if (self.highlighted) {
        
        POPBasicAnimation *scaleAnimation = [POPBasicAnimation animationWithPropertyNamed:kPOPViewScaleXY];
        scaleAnimation.duration           = 0.1f;
        scaleAnimation.toValue            = [NSValue valueWithCGPoint:CGPointMake(0.85, 0.85)];
        [self.maskImageView pop_addAnimation:scaleAnimation forKey:@"scaleAnimation"];
        
    } else {
        
        POPSpringAnimation *scaleAnimation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewScaleXY];
        scaleAnimation.toValue             = [NSValue valueWithCGPoint:CGPointMake(1, 1)];
        scaleAnimation.velocity            = [NSValue valueWithCGPoint:CGPointMake(2, 2)];
        scaleAnimation.springBounciness    = 20.f;
        [self.maskImageView pop_addAnimation:scaleAnimation forKey:@"scaleAnimation"];
    }
}

- (void)setPreviewImage:(UIImage *)previewImage {
    _previewImage = previewImage;
    self.previewImageView.image = previewImage;
}

- (void)setPreviewCheckmark:(UIImage *)previewCheckmark {
    _previewCheckmark = previewCheckmark;
    self.maskImageView.image = previewCheckmark;
}

- (void)setPreviewStyleSelected:(BOOL)selected {
    if (selected) {
        _maskImageView.alpha = 0.95;
    } else {
        _maskImageView.alpha = 0.0;
    }
}

@end
