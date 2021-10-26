//
//  iTermMetalUnavailableReason.h
//  iTerm2
//
//  Created by George Nachman on 9/29/18.
//

typedef NS_ENUM(NSUInteger, iTermMetalUnavailableReason) {
    iTermMetalUnavailableReasonNone,
    iTermMetalUnavailableReasonNoGPU,
    iTermMetalUnavailableReasonDisabled,
    iTermMetalUnavailableReasonLigatures,
    iTermMetalUnavailableReasonInitializing,
    iTermMetalUnavailableReasonInvalidSize,
    iTermMetalUnavailableReasonSessionInitializing,
    iTermMetalUnavailableReasonTransparency,
    iTermMetalUnavailableReasonVerticalSpacing,
    iTermMetalUnavailableReasonMarginSize,
    iTermMetalUnavailableReasonAnnotations,
    iTermMetalUnavailableReasonFindPanel,
    iTermMetalUnavailableReasonPasteIndicator,
    iTermMetalUnavailableReasonAnnouncement,
    iTermMetalUnavailableReasonURLPreview,
    iTermMetalUnavailableReasonWindowResizing,
    iTermMetalUnavailableReasonDisconnectedFromPower,
    iTermMetalUnavailableReasonIdle,
    iTermMetalUnavailableReasonTooManyPanesReason,
    iTermMetalUnavailableReasonNoFocus,
    iTermMetalUnavailableReasonTabInactive,
    iTermMetalUnavailableReasonTabBarTemporarilyVisible,
    iTermMetalUnavailableReasonScreensChanging,
    iTermMetalUnavailableReasonContextAllocationFailure,
    iTermMetalUnavailableReasonTabDragInProgress,
    iTermMetalUnavailableReasonSessionHasNoWindow,
    iTermMetalUnavailableReasonDropTargetsVisible,
    iTermMetalUnavailableReasonSharedBackgroundImage,
    iTermMetalUnavailableReasonSwipingBetweenTabs,
    iTermMetalUnavailableReasonSplitPaneBeingDragged,
    iTermMetalUnavailableReasonWindowObscured,
    iTermMetalUnavailableReasonLowerPowerMode
};

NSString *iTermMetalUnavailableReasonDescription(iTermMetalUnavailableReason reason);
