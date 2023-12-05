//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<integration_test/IntegrationTestPlugin.h>)
#import <integration_test/IntegrationTestPlugin.h>
#else
@import integration_test;
#endif

#if __has_include(<pdfrx/PdfrxPlugin.h>)
#import <pdfrx/PdfrxPlugin.h>
#else
@import pdfrx;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [IntegrationTestPlugin registerWithRegistrar:[registry registrarForPlugin:@"IntegrationTestPlugin"]];
  [PdfrxPlugin registerWithRegistrar:[registry registrarForPlugin:@"PdfrxPlugin"]];
}

@end
