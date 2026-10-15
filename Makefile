THEOS_PACKAGE_SCHEME = roothide
TARGET := iphone:clang:16.5:15.0
ARCHS := arm64e
INSTALL_TARGET_PROCESSES := WeChat
DEBUG := 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatGroupExtractor
WeChatGroupExtractor_FILES = WGCore.m
WeChatGroupExtractor_FRAMEWORKS = UIKit Foundation CoreGraphics
WeChatGroupExtractor_CFLAGS = -fobjc-arc -Wno-unused-parameter

include $(THEOS_MAKE_PATH)/tweak.mk
