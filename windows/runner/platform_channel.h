// platform_channel.h - Platform Channel Handler for Windows
#ifndef PLATFORM_CHANNEL_H_
#define PLATFORM_CHANNEL_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/flutter_engine.h>
#include <windows.h>
#include <memory>
#include <string>

class PlatformChannel {
public:
    static void Register(flutter::FlutterEngine* engine);

private:
    static void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    static bool SetSystemProxy(bool enable, const std::string& host, int port);
    static bool SetAutoStart(bool enable);
    static bool IsAutoStartEnabled();
    static std::map<std::string, flutter::EncodableValue> GetDeviceInfo();
    static std::string GetConfigDirectory();

    static std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
    static void SendEvent(const std::string& type, const flutter::EncodableValue& data);
};

#endif  // PLATFORM_CHANNEL_H_
