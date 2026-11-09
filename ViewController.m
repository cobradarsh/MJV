#import "ViewController.h"
#import "Shared.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <errno.h>
#import <notify.h>
#import <string.h>
#import <sys/stat.h>

@interface OCViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *chooseButton;
@property (nonatomic, strong) UIButton *blackButton;
@property (nonatomic, strong) UIButton *previewButton;
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, assign) BOOL busy;
@end

@implementation OCViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"OpenCam";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self prepareSharedDirectories];
    [self buildInterface];
    [self refreshInterface];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshInterface];
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.systemBlueColor;
    button.layer.cornerRadius = 12;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 16, 12, 16);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildInterface {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.layoutMargins = UIEdgeInsetsMake(20, 20, 30, 20);
    stack.layoutMarginsRelativeArrangement = YES;
    [scrollView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor]
    ]];

    UILabel *title = [self labelWithText:@"Virtual camera"
                                    font:[UIFont systemFontOfSize:32 weight:UIFontWeightBold]
                                   color:UIColor.labelColor];
    [stack addArrangedSubview:title];

    UILabel *subtitle = [self labelWithText:@"Loop a video or show a black screen in apps that use the camera."
                                      font:[UIFont systemFontOfSize:16]
                                     color:UIColor.secondaryLabelColor];
    [stack addArrangedSubview:subtitle];

    self.statusLabel = [self labelWithText:nil
                                     font:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium]
                                    color:UIColor.labelColor];
    [stack addArrangedSubview:self.statusLabel];

    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.hidesWhenStopped = YES;
    [stack addArrangedSubview:self.activityIndicator];

    self.chooseButton = [self buttonWithTitle:@"Choose video from Photos" action:@selector(chooseVideo)];
    [stack addArrangedSubview:self.chooseButton];

    self.previewButton = [self buttonWithTitle:@"Preview video" action:@selector(previewVideo)];
    self.previewButton.backgroundColor = UIColor.systemIndigoColor;
    [stack addArrangedSubview:self.previewButton];

    self.blackButton = [self buttonWithTitle:@"Use black screen" action:@selector(toggleBlackScreen)];
    self.blackButton.backgroundColor = UIColor.systemGrayColor;
    [stack addArrangedSubview:self.blackButton];

    UILabel *switchLabel = [self labelWithText:@"Enable virtual camera"
                                         font:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]
                                        color:UIColor.labelColor];
    self.enableSwitch = [[UISwitch alloc] init];
    [self.enableSwitch addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *switchRow = [[UIStackView alloc] initWithArrangedSubviews:@[switchLabel, self.enableSwitch]];
    switchRow.axis = UILayoutConstraintAxisHorizontal;
    switchRow.alignment = UIStackViewAlignmentCenter;
    switchRow.spacing = 12;
    [stack addArrangedSubview:switchRow];

    UILabel *warning = [self labelWithText:@"Replacing camera frames can interrupt video calls. Test before an important call. Your selected video stays on this device."
                                     font:[UIFont systemFontOfSize:13]
                                    color:UIColor.secondaryLabelColor];
    [stack addArrangedSubview:warning];
}

- (BOOL)prepareSharedDirectories {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSDictionary *attributes = @{
        NSFilePosixPermissions: @(0755),
        NSFileProtectionKey: NSFileProtectionNone
    };
    BOOL success = YES;
    for (NSString *path in @[OCSharedDirectory(), OCEnableDirectory()]) {
        NSError *error = nil;
        if (![manager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:attributes error:&error]) {
            success = NO;
        }
        [manager setAttributes:attributes ofItemAtPath:path error:nil];
    }
    return success;
}

- (BOOL)fileExists:(NSString *)path {
    return [NSFileManager.defaultManager fileExistsAtPath:path];
}

- (void)refreshInterface {
    const BOOL hasVideo = [self fileExists:OCVideoPath()];
    const BOOL black = [self fileExists:OCBlackScreenPath()];
    const BOOL enabled = [self fileExists:OCEnabledPath()];

    self.enableSwitch.on = enabled;
    [self.chooseButton setTitle:hasVideo ? @"Replace video" : @"Choose video from Photos"
                       forState:UIControlStateNormal];
    [self.blackButton setTitle:(hasVideo && black) ? @"Use selected video" : @"Use black screen"
                      forState:UIControlStateNormal];
    self.previewButton.enabled = hasVideo && !self.busy;
    self.chooseButton.enabled = !self.busy;
    self.blackButton.enabled = !self.busy;
    self.enableSwitch.enabled = !self.busy;

    if (enabled && black) {
        self.statusLabel.text = @"Active · black screen";
    } else if (enabled && hasVideo) {
        self.statusLabel.text = @"Active · looping video";
    } else if (enabled) {
        self.statusLabel.text = @"Active · no readable source, using black";
    } else if (black) {
        self.statusLabel.text = @"Black screen selected. Enable when ready.";
    } else if (hasVideo) {
        self.statusLabel.text = @"Video ready. Enable when ready.";
    } else {
        self.statusLabel.text = @"Choose a video or use a black screen.";
    }
}

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    self.busy = busy;
    if (busy) {
        [self.activityIndicator startAnimating];
    } else {
        [self.activityIndicator stopAnimating];
    }
    [self refreshInterface];
    if (status != nil) {
        self.statusLabel.text = status;
    }
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)writeMarkerAtPath:(NSString *)path {
    if (![self prepareSharedDirectories]) {
        return NO;
    }
    NSError *error = nil;
    if (![@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        return NO;
    }
    [NSFileManager.defaultManager setAttributes:@{
        NSFilePosixPermissions: @(0644),
        NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:path error:nil];
    return YES;
}

- (void)notifyEngine {
    notify_post(OCChangeNotification.UTF8String);
}

- (void)chooseVideo {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    configuration.filter = PHPickerFilter.videosFilter;
    configuration.selectionLimit = 1;
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (provider == nil) {
        return;
    }
    if (![provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier]) {
        [self showMessage:@"The selected item is not a video." title:@"Import failed"];
        return;
    }

    [self setBusy:YES status:@"Importing video…"];
    if (![self prepareSharedDirectories]) {
        [self setBusy:NO status:nil];
        [self showMessage:@"Could not create the shared video folder." title:@"Import failed"];
        return;
    }

    [provider loadFileRepresentationForTypeIdentifier:UTTypeMovie.identifier
                                    completionHandler:^(NSURL *url, NSError *error) {
        if (url == nil || error != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setBusy:NO status:nil];
                [self showMessage:error.localizedDescription ?: @"Photos did not provide a readable video." title:@"Import failed"];
            });
            return;
        }

        // The picker owns this temporary URL only for the duration of the callback.
        NSString *incoming = [OCSharedDirectory() stringByAppendingFormat:@"/incoming-%@.mov", NSUUID.UUID.UUIDString];
        NSError *copyError = nil;
        BOOL copied = [NSFileManager.defaultManager copyItemAtURL:url
                                                            toURL:[NSURL fileURLWithPath:incoming]
                                                            error:&copyError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!copied) {
                [self setBusy:NO status:nil];
                [self showMessage:copyError.localizedDescription title:@"Import failed"];
                return;
            }
            [self exportVideoAtPath:incoming];
        });
    }];
}

- (void)exportVideoAtPath:(NSString *)inputPath {
    [self setBusy:YES status:@"Preparing MP4…"];
    AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:inputPath]];
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:asset
                                                                      presetName:AVAssetExportPresetHighestQuality];
    if (exporter == nil || ![exporter.supportedFileTypes containsObject:AVFileTypeMPEG4]) {
        [NSFileManager.defaultManager removeItemAtPath:inputPath error:nil];
        [self setBusy:NO status:nil];
        [self showMessage:@"This video cannot be exported as MP4." title:@"Import failed"];
        return;
    }

    NSString *outputPath = [OCSharedDirectory() stringByAppendingFormat:@"/ready-%@.mp4", NSUUID.UUID.UUIDString];
    exporter.outputURL = [NSURL fileURLWithPath:outputPath];
    exporter.outputFileType = AVFileTypeMPEG4;
    exporter.shouldOptimizeForNetworkUse = YES;

    [exporter exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSFileManager.defaultManager removeItemAtPath:inputPath error:nil];
            if (exporter.status != AVAssetExportSessionStatusCompleted) {
                [NSFileManager.defaultManager removeItemAtPath:outputPath error:nil];
                [self setBusy:NO status:nil];
                [self showMessage:exporter.error.localizedDescription ?: @"Video export failed." title:@"Import failed"];
                return;
            }
            [self publishVideoAtPath:outputPath];
        });
    }];
}

- (void)publishVideoAtPath:(NSString *)outputPath {
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager setAttributes:@{
        NSFilePosixPermissions: @(0644),
        NSFileProtectionKey: NSFileProtectionNone
    } ofItemAtPath:outputPath error:nil];

    // source.mp4 stays on the same filesystem, so rename is atomic. The engine
    // sees either the complete old video or the complete new video.
    if (rename(outputPath.fileSystemRepresentation, OCVideoPath().fileSystemRepresentation) != 0) {
        const int errorCode = errno;
        [manager removeItemAtPath:outputPath error:nil];
        [self setBusy:NO status:nil];
        [self showMessage:[NSString stringWithFormat:@"Could not publish the video (%s).", strerror(errorCode)]
                    title:@"Import failed"];
        return;
    }

    [manager removeItemAtPath:OCBlackScreenPath() error:nil];
    [self notifyEngine];
    [self setBusy:NO status:nil];
    [self showMessage:@"Video saved. Enable OpenCam and test a video call." title:@"Ready"];
}

- (void)previewVideo {
    if (![self fileExists:OCVideoPath()]) {
        [self showMessage:@"Choose a video first." title:@"No video"];
        return;
    }
    AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:OCVideoPath()]];
    AVPlayerViewController *controller = [[AVPlayerViewController alloc] init];
    controller.player = player;
    [self presentViewController:controller animated:YES completion:^{
        [player play];
    }];
}

- (void)toggleBlackScreen {
    if ([self fileExists:OCVideoPath()] && [self fileExists:OCBlackScreenPath()]) {
        [NSFileManager.defaultManager removeItemAtPath:OCBlackScreenPath() error:nil];
    } else if (![self writeMarkerAtPath:OCBlackScreenPath()]) {
        [self showMessage:@"Could not select black-screen mode." title:@"Error"];
        return;
    }
    [self notifyEngine];
    [self refreshInterface];
}

- (void)toggleChanged:(UISwitch *)sender {
    if (!sender.on) {
        [NSFileManager.defaultManager removeItemAtPath:OCEnabledPath() error:nil];
        [self notifyEngine];
        [self refreshInterface];
        return;
    }

    if (![self fileExists:OCVideoPath()] && ![self fileExists:OCBlackScreenPath()]) {
        sender.on = NO;
        [self showMessage:@"Choose a video or select black-screen mode first." title:@"No source"];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enable virtual camera?"
                                                                   message:@"Other apps will receive the selected source instead of the real camera. Active video calls may be interrupted."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak OCViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        weakSelf.enableSwitch.on = NO;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Enable" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        OCViewController *strongSelf = weakSelf;
        if (![strongSelf writeMarkerAtPath:OCEnabledPath()]) {
            [strongSelf showMessage:@"Could not enable camera replacement." title:@"Error"];
        }
        [strongSelf notifyEngine];
        [strongSelf refreshInterface];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
