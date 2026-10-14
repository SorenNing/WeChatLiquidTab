THEOS_PACKAGE_SCHEME = roothide
TARGET := iphone:clang:16.5:15.0
ARCHS = arm64e

INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatLiquidTab
WeChatLiquidTab_FILES = Tweak.x SettingViewController.m
WeChatLiquidTab_FRAMEWORKS = UIKit QuartzCore CoreGraphics
WeChatLiquidTab_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
