
#import "THPreviewView.h"
#import "NSTimer+Additions.h"

#define BOX_BOUNDS CGRectMake(0.0f, 0.0f, 150, 150.0f)

@interface THPreviewView ()
@property (strong, nonatomic) UIView *focusBox;
@property (strong, nonatomic) UIView *exposureBox;
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) UITapGestureRecognizer *singleTapRecognizer;
@property (strong, nonatomic) UITapGestureRecognizer *doubleTapRecognizer;
@property (strong, nonatomic) UITapGestureRecognizer *doubleDoubleTapRecognizer;
@end

@implementation THPreviewView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupView];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)setupView
{
    [(AVCaptureVideoPreviewLayer *)self.layer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    _singleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    _doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    _doubleTapRecognizer.numberOfTapsRequired = 2;
    _doubleDoubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleDoubleTap:)];
    _doubleDoubleTapRecognizer.numberOfTapsRequired = 2;
    _doubleDoubleTapRecognizer.numberOfTouchesRequired = 2;
    
    [self addGestureRecognizer:_singleTapRecognizer];
    [self addGestureRecognizer:_doubleTapRecognizer];
    [self addGestureRecognizer:_doubleDoubleTapRecognizer];
    
    _focusBox = [self viewWithColor:[UIColor colorWithRed:0.102 green:0.636 blue:1.000 alpha:1.000]];
    _exposureBox = [self viewWithColor:[UIColor colorWithRed:1.000 green:0.421 blue:0.054 alpha:1.000]];
    [self addSubview:_focusBox];
    [self addSubview:_exposureBox];
}

- (UIView *)viewWithColor:(UIColor *)color {
    UIView *view = [[UIView alloc] initWithFrame:BOX_BOUNDS];
    view.backgroundColor = [UIColor clearColor];
    view.layer.borderColor = color.CGColor;
    view.layer.borderWidth = 5.0f;
    view.hidden = YES;
    return view;
}

- (void)runBoxAnimationOnView:(UIView *)view point:(CGPoint)point
{
    view.center = point;
    view.hidden = NO;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        view.transform = CGAffineTransformMakeScale(0.5, 0.5);
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            view.hidden = YES;
            view.transform = CGAffineTransformIdentity;
        });
    }];
}

/// reset 聚光，曝光点
- (void)runResetAnimation {
    if (!self.tapToFocusEnabled && !self.tapToExposeEnabled) {
        return;
    }
    AVCaptureVideoPreviewLayer *layer = (AVCaptureVideoPreviewLayer *)self.layer;
    // 设备坐标 -> layer坐标
    CGPoint centerPoint = [layer pointForCaptureDevicePointOfInterest:CGPointMake(0.5, 0.5)];
    self.focusBox.center = centerPoint;
    self.exposureBox.center = centerPoint;
    self.exposureBox.transform = CGAffineTransformMakeScale(1.2, 1.2);
    self.focusBox.hidden = NO;
    self.exposureBox.hidden = NO;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.focusBox.transform = CGAffineTransformMakeScale(0.5, 0.5);
        self.exposureBox.transform = CGAffineTransformMakeScale(0.7, 0.7);
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.focusBox.hidden = YES;
            self.exposureBox.hidden = YES;
            self.focusBox.transform = CGAffineTransformIdentity;
            self.exposureBox.transform = CGAffineTransformIdentity;
        });
    }];
}

//私有方法 用于支持该类定义的不同触摸处理方法。 将屏幕坐标系上的触控点转换为摄像头上的坐标系点
- (CGPoint)captureDevicePointForPoint:(CGPoint)point {
    AVCaptureVideoPreviewLayer *layer =
    (AVCaptureVideoPreviewLayer *)self.layer;
    return [layer captureDevicePointOfInterestForPoint:point];
}

// MARK: - Action
- (void)handleSingleTap: (UIGestureRecognizer *)recognizer
{
    CGPoint point = [recognizer locationInView:self];
    [self runBoxAnimationOnView:self.focusBox point:point];
    if (self.delegate) {
        [self.delegate tappedToFocusAtPoint:[self captureDevicePointForPoint:point]];
    }
}

- (void)handleDoubleTap: (UIGestureRecognizer *)recognizer
{
    CGPoint point = [recognizer locationInView:self];
    [self runBoxAnimationOnView:self.exposureBox point:point];
    if (self.delegate) {
        [self.delegate tappedToExposeAtPoint:[self captureDevicePointForPoint:point]];
    }
}

- (void)handleDoubleDoubleTap: (UIGestureRecognizer *)recoginer
{
    [self runResetAnimation];
    if (self.delegate) {
        [self.delegate tappedToResetFocusAndExposure];
    }
}

/// 重写layerClass
+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

// MARK: - Getter & Setter
- (void)setSession:(AVCaptureSession *)session
{
    [(AVCaptureVideoPreviewLayer *)self.layer setSession:session];
}

- (AVCaptureSession *)session
{
    return [(AVCaptureVideoPreviewLayer *)self.layer session];
}

- (void)setTapToFocusEnabled:(BOOL)enabled {
    _tapToFocusEnabled = enabled;
    self.singleTapRecognizer.enabled = enabled;
}

- (void)setTapToExposeEnabled:(BOOL)enabled {
    _tapToExposeEnabled = enabled;
    self.doubleTapRecognizer.enabled = enabled;
}

@end
