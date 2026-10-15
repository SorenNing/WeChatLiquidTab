TARGET := iphone:clang:16.5:15.0
ARCHS := arm64e
INSTALL_TARGET_PROCESSES := WeChat
DEBUG := 0
TWEAK_NAME = WeChatGroupExtractor
WeChatGroupExtractor_FILES = Tweak.x
WeChatGroupExtractor_CFLAGS = -fobjc-arc
include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk