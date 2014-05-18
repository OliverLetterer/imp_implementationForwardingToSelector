# imp_implementationForwardingToSelector

[![Version](http://cocoapod-badges.herokuapp.com/v/imp_implementationForwardingToSelector/badge.png)](http://cocoadocs.org/docsets/imp_implementationForwardingToSelector)
[![Platform](http://cocoapod-badges.herokuapp.com/p/imp_implementationForwardingToSelector/badge.png)](http://cocoadocs.org/docsets/imp_implementationForwardingToSelector)
[![License Badge](https://go-shields.herokuapp.com/license-MIT-blue.png)](https://go-shields.herokuapp.com/license-MIT-blue.png)

`imp_implementationForwardingToSelector` is a trampoline that forwards an objc message to a different selector.

## Installation

`imp_implementationForwardingToSelector` is available through [CocoaPods](http://cocoapods.org), to install
it simply add the following line to your Podfile:

``` ruby
pod "imp_implementationForwardingToSelector"
```

## How it works

### Message forwarding

`imp_implementationForwardingToSelector` is a custom trampoline (you can read about trampolines [here](http://landonf.bikemonkey.org/2011/04/index.html)) which can forward any objc message to a new selector.

``` objc
IMP imp_implementationForwardingToSelector(SEL forwardingSelector, BOOL returnsAStructValue);
```

Here is an example

``` objc
IMP forwardingImplementation = imp_implementationForwardingToSelector(@selector(setCenter:), NO);
class_addMethod([UIView class], @selector(thisSetCenterDoesNotExistYet:), forwardingImplementation, typeEncoding);
```

and suddenly every instance of `UIView` responds to `-[UIView thisSetCenterDoesNotExistYet:]` and forwards this message to `-[UIView setCenter:]`. If you would like some more information about trampolines and maybe a blog post like `Writing custom trampolines for beginners and all the pitfalls`, hit me up on [Twitter](http://twitter.com/oletterer).

## Limitations

`imp_implementationForwardingToSelector` is written in raw assembly which is currently only available on i386, armv7, armv7s and arm64.

## Author

Oliver Letterer

- http://github.com/OliverLetterer
- http://twitter.com/oletterer
- oliver.letterer@gmail.com

## License

imp_implementationForwardingToSelector is available under the MIT license. See the LICENSE file for more info.
