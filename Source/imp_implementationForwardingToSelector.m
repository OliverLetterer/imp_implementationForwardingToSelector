//
//  imp_implementationForwardingToSelector.m
//  imp_implementationForwardingToSelector
//
//  Created by Oliver Letterer on 22.03.14.
//  Copyright 2014 Sparrowlabs. All rights reserved.
//

#import "imp_implementationForwardingToSelector.h"
#import <objc/message.h>
#import <AssertMacros.h>
#import <libkern/OSAtomic.h>

#import <mach/vm_types.h>
#import <mach/vm_map.h>
#import <mach/mach_init.h>

extern id spl_forwarding_trampoline_page(id, SEL);
extern id spl_forwarding_trampoline_stret_page(id, SEL);

static OSSpinLock lock = OS_SPINLOCK_INIT;

typedef struct {
#ifndef __arm64__
    IMP msgSend;
#endif
    SEL selector;
} SPLForwardingTrampolineDataBlock;

#if defined(__arm64__)
typedef int32_t SPLForwardingTrampolineEntryPointBlock[2];
static const int32_t SPLForwardingTrampolineInstructionCount = 6;
#elif defined(_ARM_ARCH_7)
typedef int32_t SPLForwardingTrampolineEntryPointBlock[2];
static const int32_t SPLForwardingTrampolineInstructionCount = 4;
#elif defined(__i386__)
typedef int32_t SPLForwardingTrampolineEntryPointBlock[2];
static const int32_t SPLForwardingTrampolineInstructionCount = 6;
#else
#error SPLMessageLogger is not supported on this platform
#endif

static const size_t numberOfTrampolinesPerPage = (PAGE_SIZE - SPLForwardingTrampolineInstructionCount * sizeof(int32_t)) / sizeof(SPLForwardingTrampolineEntryPointBlock);

typedef struct {
    union {
        struct {
            IMP msgSend;
            int32_t nextAvailableTrampolineIndex;
        };
        int32_t trampolineSize[SPLForwardingTrampolineInstructionCount];
    };

    SPLForwardingTrampolineDataBlock trampolineData[numberOfTrampolinesPerPage];

    int32_t trampolineInstructions[SPLForwardingTrampolineInstructionCount];
    SPLForwardingTrampolineEntryPointBlock trampolineEntryPoints[numberOfTrampolinesPerPage];
} SPLForwardingTrampolinePage;

check_compile_time(sizeof(SPLForwardingTrampolineEntryPointBlock) == sizeof(SPLForwardingTrampolineDataBlock));
check_compile_time(sizeof(SPLForwardingTrampolinePage) == 2 * PAGE_SIZE);
check_compile_time(offsetof(SPLForwardingTrampolinePage, trampolineInstructions) == PAGE_SIZE);

static SPLForwardingTrampolinePage *SPLForwardingTrampolinePageAlloc(BOOL useObjcMsgSendStret)
{
    vm_address_t trampolineTemplatePage = useObjcMsgSendStret ? (vm_address_t)&spl_forwarding_trampoline_stret_page : (vm_address_t)&spl_forwarding_trampoline_page;

    vm_address_t newTrampolinePage = 0;
    kern_return_t kernReturn = KERN_SUCCESS;

    // allocate two consequent memory pages
    kernReturn = vm_allocate(mach_task_self(), &newTrampolinePage, PAGE_SIZE * 2, VM_FLAGS_ANYWHERE);
    NSCAssert1(kernReturn == KERN_SUCCESS, @"vm_allocate failed", kernReturn);

    // deallocate second page where we will store our trampoline
    vm_address_t trampoline_page = newTrampolinePage + PAGE_SIZE;
    kernReturn = vm_deallocate(mach_task_self(), trampoline_page, PAGE_SIZE);
    NSCAssert1(kernReturn == KERN_SUCCESS, @"vm_deallocate failed", kernReturn);

    // trampoline page will be remapped with implementation of spl_objc_forwarding_trampoline
    vm_prot_t cur_protection, max_protection;
    kernReturn = vm_remap(mach_task_self(), &trampoline_page, PAGE_SIZE, 0, 0, mach_task_self(), trampolineTemplatePage, FALSE, &cur_protection, &max_protection, VM_INHERIT_SHARE);
    NSCAssert1(kernReturn == KERN_SUCCESS, @"vm_remap failed", kernReturn);

    return (void *)newTrampolinePage;
}

static SPLForwardingTrampolinePage *nextTrampolinePage(BOOL returnStructValue)
{
    static NSMutableArray *normalTrampolinePages = nil;
    static NSMutableArray *structReturnTrampolinePages = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        normalTrampolinePages = [NSMutableArray array];
        structReturnTrampolinePages = [NSMutableArray array];
    });

    NSMutableArray *thisArray = returnStructValue ? structReturnTrampolinePages : normalTrampolinePages;

    SPLForwardingTrampolinePage *trampolinePage = [thisArray.lastObject pointerValue];

    if (!trampolinePage) {
        trampolinePage = SPLForwardingTrampolinePageAlloc(returnStructValue);
        [thisArray addObject:[NSValue valueWithPointer:trampolinePage]];
    }

    if (trampolinePage->nextAvailableTrampolineIndex == numberOfTrampolinesPerPage) {
        // trampoline page is full
        trampolinePage = SPLForwardingTrampolinePageAlloc(returnStructValue);
        [thisArray addObject:[NSValue valueWithPointer:trampolinePage]];
    }

    trampolinePage->msgSend = objc_msgSend;
    return trampolinePage;
}

IMP imp_implementationForwardingToSelector(SEL forwardingSelector, BOOL returnsAStructValue)
{
    OSSpinLockLock(&lock);

#ifdef __arm64__
    returnsAStructValue = NO;
#endif

    SPLForwardingTrampolinePage *dataPageLayout = nextTrampolinePage(returnsAStructValue);

    int32_t nextAvailableTrampolineIndex = dataPageLayout->nextAvailableTrampolineIndex;
#ifndef __arm64__
    dataPageLayout->trampolineData[nextAvailableTrampolineIndex].msgSend = returnsAStructValue ? (IMP)objc_msgSend_stret : objc_msgSend;
#endif

    dataPageLayout->trampolineData[nextAvailableTrampolineIndex].selector = forwardingSelector;
    dataPageLayout->nextAvailableTrampolineIndex++;

    IMP implementation = (IMP)&dataPageLayout->trampolineEntryPoints[nextAvailableTrampolineIndex];

    OSSpinLockUnlock(&lock);
    return implementation;
}
