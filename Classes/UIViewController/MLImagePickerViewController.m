//
//  MLImagePickerViewController.m
//  MLPhotoLib
//
//  Created by leisuro on 16/8/1.
//  Copyright © 2016年 Free. All rights reserved.
//

#import "MLImagePickerViewController.h"
#import "MLImagePickerViewController+MenuTableViewDataSource.h"
#import "MLNavigationViewController.h"
#import "MLPhotoPickerCollectionView.h"
#import "MLPhotoPickerCollectionView.h"
#import "MLImagePickerMenuTableViewCell.h"
#import "MLPhotoPickerData.h"
#import "MLPhotoKitData.h"
#import "MLPhotoPickerAssetsManager.h"
#import "MLPhotoAsset.h"
#import "MLPhotoPickerManager.h"
#import "UIButton+Animation.h"

typedef void(^completionHandle)(BOOL success, NSArray<NSURL *>*assetUrls, NSArray<UIImage *>*thumbImages, NSArray<UIImage *>*originalImages, NSError *error);

@interface MLImagePickerViewController () <PHPhotoLibraryChangeObserver>

@property (nonatomic, weak) UIView *groupView;
@property (nonatomic, weak) UITableView *groupTableView;
@property (nonatomic, strong) MLPhotoPickerCollectionView *contentCollectionView;
@property (nonatomic, weak) UIButton *tagRightBtn;

@property (nonatomic, strong) MLPhotoPickerAssetsManager *imageManager;
@property (nonatomic, strong) MLPhotoPickerManager *pickerManager;
@property (nonatomic, strong) PHFetchResult *fetchResult;
@property (nonatomic, copy) completionHandle completion;
@end

@implementation MLImagePickerViewController

- (void)displayForVC:(__weak UIViewController *)viewController completionHandle:(void (^)(BOOL, NSArray<NSURL *> *, NSArray<UIImage *> *, NSArray<UIImage *> *, NSError *))completionHandle
{
    if (gtiOS8)
    {
        if (![MLPhotoKitData judgeIsHavePhotoAblumAuthority])
        {
            NSError *error = [NSError errorWithDomain:@"com.github.makezl" code:-11 userInfo:@{@"errorMsg":@"用户没有开启选择相片的权限!"}];
            !completionHandle?:completionHandle(NO, nil, nil, nil, error);
            return;
        }
    } else {
        if (![MLPhotoPickerData judgeIsHavePhotoAblumAuthority])
        {
            NSError *error = [NSError errorWithDomain:@"com.github.makezl" code:-11 userInfo:@{@"errorMsg":@"用户没有开启选择相片的权限!"}];
            !completionHandle?:completionHandle(NO, nil, nil, nil, error);
            return;
        }
    }
    self.completion = completionHandle;
    [MLPhotoPickerManager manager].presentViewController = viewController;
    [MLPhotoPickerManager manager].navigationController = [[MLNavigationViewController alloc] initWithRootViewController:self];
    [viewController presentViewController:[MLPhotoPickerManager manager].navigationController animated:YES completion:nil];
}

+ (instancetype)new
{
    return [[self alloc] init];
}

+ (instancetype)pickerViewController
{
    return [[self alloc] init];
}

- (instancetype)init
{
    if (self = [super init]) {
        self.isSupportTakeCamera = YES;
        self.maxCount = MLDefaultMaxCount;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setup];
}

- (void)setup
{
    [self.view setBackgroundColor:[UIColor whiteColor]];
    [self setupSubviews];
    [self setupPickerData];
    [self addSelectAssetNotification];
}

- (void)setupSubviews
{
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.navigationItem.titleView = [self addTitleView];
    [self addNavigationBarRightView];
    [self.view addSubview:_contentCollectionView = [[MLPhotoPickerCollectionView alloc] initWithFrame:(CGRect){CGPointMake(0, 34), CGSizeMake(self.view.frame.size.width, self.view.frame.size.height - self.navigationController.navigationBar.frame.size.height)}]];
}

- (void)setupPickerData
{
    if (gtiOS8) {
        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
        self.imageManager = [[MLPhotoPickerAssetsManager alloc] init];
        self.fetchResult = [self.imageManager fetchResult];
        
        [self setupGroup];
        
        NSMutableArray *assets = @[].mutableCopy;
        for (NSInteger i = 0; i < self.fetchResult.count; i++){
            MLPhotoAsset *asset = [[MLPhotoAsset alloc] init];
            asset.asset = self.fetchResult[i];
            [assets addObject:asset];
        }
        self.contentCollectionView.albumAssets = assets;
        self.contentCollectionView.group = [self.groups firstObject];
    } else {
        WeakSelf
        MLPhotoPickerData *pickerData = [MLPhotoPickerData pickerData];
        [pickerData getAllGroup:^(NSArray *groups) {
            weakSelf.groups = groups;
            [weakSelf groupsWithAsset:groups];
        }];
    }
}

- (void)setupGroup
{
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    [options setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]]];
    PHFetchResult *allPhotos = [PHAsset fetchAssetsWithOptions:options];
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    PHFetchResult *userCollections = [PHCollectionList fetchTopLevelUserCollectionsWithOptions:nil];
    
    NSMutableArray *groups = @[].mutableCopy;
    NSArray *collections = @[allPhotos,smartAlbums,userCollections];
    for (PHFetchResult *result in collections)
    {
        for (PHAssetCollection *collection in result)
        {
            if ([collection isKindOfClass:[PHAssetCollection class]])
            {
                // Filter empty Assets.
                PHFetchResult *collectionResult = [PHAsset fetchAssetsInAssetCollection:collection options:nil];
                if (collectionResult.count > 0)
                {
                    MLPhotoPickerGroup *group = [[MLPhotoPickerGroup alloc] init];
                    group.collection = collection;
                    [groups addObject:group];
                }
            }
        }
    }
    self.groups = groups;
}

- (void)addSelectAssetNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationDidChangeSelectUrl) name:MLNotificationDidChangeSelectUrl object:nil];
}

- (void)groupsWithAsset:(NSArray *)groups
{
    for (MLPhotoPickerGroup *group in groups) {
        if ([group.type integerValue] == 16) {
            // 相机胶卷
            [self reloadCollectionViewWithGroup:group];
            break;
        }
    }
}

- (void)reloadCollectionViewWithGroup:(MLPhotoPickerGroup *)group
{
    UIButton *titleBtn = [[self.navigationItem.titleView subviews] lastObject];
    [titleBtn setTitle:[group groupName] forState:UIControlStateNormal];
    if (gtiOS8) {
        PHFetchOptions *options = [[PHFetchOptions alloc] init];
        [options setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]]];
        self.fetchResult = [PHAsset fetchAssetsInAssetCollection:group.collection options:options];
        
        NSMutableArray *assets = [NSMutableArray arrayWithCapacity:self.fetchResult.count];
        for (NSInteger i = 0; i < self.fetchResult.count; i++){
            MLPhotoAsset *asset = [[MLPhotoAsset alloc] init];
            asset.asset = self.fetchResult[i];
            [assets addObject:asset];
        }
        self.contentCollectionView.group = group;
        self.contentCollectionView.albumAssets = assets;
    } else {
        WeakSelf
        [[MLPhotoPickerData pickerData] getGroupPhotosWithGroup:group finished:^(NSArray *assets) {
            NSMutableArray *tmpArrayM = [NSMutableArray arrayWithCapacity:assets.count];
            assets = [[assets reverseObjectEnumerator] allObjects];
            for (ALAsset *asset in assets) {
                __block MLPhotoAsset *mlAsset = [[MLPhotoAsset alloc] init];
                mlAsset.asset = asset;
                [tmpArrayM addObject:mlAsset];
            }
            weakSelf.contentCollectionView.group = group;
            weakSelf.contentCollectionView.albumAssets = tmpArrayM;
        }];
    }
}

#pragma mark - lazy
- (UIView *)addTitleView
{
    return ({
        if (self.navigationItem.titleView != nil) {
            return self.navigationItem.titleView;
        }
        UIView *titleView = [[UIView alloc] init];
        titleView.frame = CGRectMake(0, 0, 200, 44);
        UIButton *titleButton = [UIButton buttonWithType:UIButtonTypeCustom];
        titleButton.frame = titleView.frame;
        titleButton.titleLabel.font = [UIFont systemFontOfSize:14];
        titleButton.adjustsImageWhenHighlighted = NO;
        [titleButton setImage:[UIImage imageNamed:@"MLImagePickerController.bundle/zl_xialajiantou"] forState:UIControlStateNormal];
        [titleButton setTitleEdgeInsets:UIEdgeInsetsMake(0, 10, 0, 0)];
        [titleButton setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
        [titleButton setTitle:@"Camera Roll" forState:UIControlStateNormal];
        [titleButton addTarget:self action:@selector(tappendTitleView) forControlEvents:UIControlEventTouchUpInside];
        [titleView addSubview:titleButton];
        titleView;
    });
}

- (void)addNavigationBarRightView
{
    ({
        UIView *rightView = [[UIView alloc] init];
        rightView.frame = CGRectMake(self.view.frame.size.width - 60, 0, 40, 44);
        UIButton *rightBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        rightBtn.titleLabel.font = [UIFont systemFontOfSize:14];
        [rightBtn setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
        [rightBtn setFrame:rightView.bounds];
        [rightBtn setTitle:@"完成" forState:UIControlStateNormal];
        [rightBtn addTarget:self action:@selector(tappendDoneBtn) forControlEvents:UIControlEventTouchUpInside];
        [rightView addSubview:rightBtn];
        [self.navigationController.navigationBar addSubview:rightView];
        
        UIButton *tagRightBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        tagRightBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        tagRightBtn.titleLabel.textColor = [UIColor whiteColor];
        tagRightBtn.titleLabel.font = [UIFont systemFontOfSize:12];
        tagRightBtn.layer.cornerRadius = 10;
        tagRightBtn.frame = CGRectMake(30, 0, 20, 20);
        tagRightBtn.backgroundColor = [UIColor redColor];
        [rightView addSubview:_tagRightBtn = tagRightBtn];
        
        [self notificationDidChangeSelectUrl];
    });
}

- (UITableView *)groupTableView
{
    return ({
        if (!_groupTableView) {
            UITableView *groupTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 64, self.view.frame.size.width, 250) style:UITableViewStylePlain];
            groupTableView.backgroundColor = [UIColor whiteColor];
            groupTableView.dataSource = self;
            groupTableView.delegate = self;
            groupTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
            [groupTableView registerNib:[UINib nibWithNibName:NSStringFromClass([MLImagePickerMenuTableViewCell class]) bundle:nil] forCellReuseIdentifier:NSStringFromClass([MLImagePickerMenuTableViewCell class])];
            [self.groupView addSubview:_groupTableView = groupTableView];
        }
        _groupTableView;
    });
}

- (UIView *)groupView
{
    return ({
        if (!_groupView) {
            UIView *groupView = [[UIView alloc] initWithFrame:self.view.bounds];
            groupView.alpha = 0.0;
            groupView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
            [groupView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappendTitleView)]];
            [self.view addSubview:_groupView = groupView];
            
            [self groupTableView];
        }
        _groupView;
    });
}

- (MLPhotoPickerManager *)pickerManager
{
    if (!_pickerManager) {
        _pickerManager = [MLPhotoPickerManager manager];
    }
    return _pickerManager;
}

- (void)setSelectAssetsURL:(NSArray<NSURL *> *)selectAssetsURL
{
    _selectAssetsURL = selectAssetsURL;
    
    [MLPhotoPickerManager manager].selectsUrls = selectAssetsURL.mutableCopy;
}

- (void)setMaxCount:(NSUInteger)maxCount
{
    _maxCount = maxCount;
    
    [MLPhotoPickerManager manager].maxCount = maxCount;
}

- (void)setIsSupportTakeCamera:(BOOL)isSupportTakeCamera
{
    _isSupportTakeCamera = isSupportTakeCamera;
    
    [MLPhotoPickerManager manager].isSupportTakeCamera = isSupportTakeCamera;
}

- (void)tappendTitleView
{
    ({
        UIView *titleView = self.navigationItem.titleView;
        UIButton *titleBtn = [[titleView subviews] lastObject];
        
        [UIView animateWithDuration:0.25 animations:^{
            titleBtn.imageView.transform = (self.groupView.alpha == 1.0) ? CGAffineTransformMakeRotation(0) : CGAffineTransformMakeRotation(M_PI);
            self.groupView.alpha = (self.groupView.alpha == 1.0) ? 0.0 : 1.0;
        }];
    });
}

- (void)tappendDoneBtn
{
    !self.completion?:self.completion(YES, [self.pickerManager.selectsUrls mutableCopy], [self.pickerManager.thumbImages mutableCopy], [self.pickerManager.originalImage mutableCopy], nil);
    // Clear Select Data.
    [MLPhotoPickerManager clear];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)notificationDidChangeSelectUrl
{
    NSInteger selectsUrlsCount = [MLPhotoPickerManager manager].selectsUrls.count;
    self.tagRightBtn.hidden = (selectsUrlsCount < 1);
    [self.tagRightBtn setTitle:@(selectsUrlsCount).stringValue forState:UIControlStateNormal];
    
    [self.tagRightBtn startScaleAnimation];
}

- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    NSMutableDictionary *dict = [changeInstance valueForKey:@"_collectionChangeDetailsForObjects"];
    
    for (PHFetchResultChangeDetails *detail in [dict allValues]) {
        if (detail.fetchResultAfterChanges.count > detail.fetchResultBeforeChanges.count &&
            detail.fetchResultAfterChanges.count > self.contentCollectionView.albumAssets.count) {
            // Insert
            self.fetchResult = detail.fetchResultAfterChanges;
            
            NSMutableArray *assets = self.contentCollectionView.albumAssets.mutableCopy;
            MLPhotoAsset *asset = [[MLPhotoAsset alloc] init];
            asset.asset = [self.fetchResult firstObject];
            [assets insertObject:asset atIndex:0];
            
            NSURL *assetURL = [asset assetURL];
            if (assetURL != nil) {
                // Recoder Take Camera
                [[MLPhotoPickerManager manager].selectsUrls addObject:assetURL];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.contentCollectionView.albumAssets = assets;
            });
        }
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (gtiOS8) {
        [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
    }
}

@end
