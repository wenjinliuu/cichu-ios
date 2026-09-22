#!/usr/bin/env python3
"""Generate a deterministic Xcode project using only Python stdlib; does not build."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def oid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def add(key, isa, **kwargs):
    identifier = oid(key)
    objects[identifier] = dict(isa=isa, **kwargs)
    return identifier

def configuration(name, settings):
    return add('config:' + name, 'XCBuildConfiguration', buildSettings=settings, name=name.split(':')[-1])
def config_list(key, settings):
    refs=[]
    for name in ('Debug', 'Release'):
        s=dict(settings)
        s['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if name=='Debug' else '-O'
        if name=='Debug': s['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'; s['ENABLE_TESTABILITY']='YES'
        refs.append(configuration(key+':'+name,s))
    return add('configs:'+key,'XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

source_refs=[]; source_builds=[]; test_refs=[]; test_builds=[]
for folder, refs, builds in [('Cichu',source_refs,source_builds),('CichuTests',test_refs,test_builds)]:
    for path in sorted((ROOT/folder).rglob('*.swift')):
        rel=path.relative_to(ROOT).as_posix()
        ref=add('file:'+rel,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>')
        refs.append(ref)
        builds.append(add('build:'+rel,'PBXBuildFile',fileRef=ref))
resources=[]
for rel, typ in [('Cichu/Resources/Assets.xcassets','folder.assetcatalog'),('Cichu/Resources/PrivacyInfo.xcprivacy','text.xml')]:
    ref=add('file:'+rel,'PBXFileReference',lastKnownFileType=typ,path=rel,sourceTree='<group>')
    source_refs.append(ref)
    resources.append(add('build:'+rel,'PBXBuildFile',fileRef=ref))
info=add('info','PBXFileReference',lastKnownFileType='text.plist.xml',path='Cichu/Resources/Info.plist',sourceTree='<group>')
source_refs.append(info)
app_product=add('app-product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='Cichu.app',sourceTree='BUILT_PRODUCTS_DIR')
test_product=add('test-product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='CichuTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=[app_product,test_product],name='Products',sourceTree='<group>')
app_group=add('app-group','PBXGroup',children=source_refs,name='Cichu',sourceTree='<group>')
test_group=add('test-group','PBXGroup',children=test_refs,name='CichuTests',sourceTree='<group>')
main_group=add('main-group','PBXGroup',children=[app_group,test_group,products],sourceTree='<group>')
def phase(key, isa, files):
    return add(key,isa,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
app_phases=[phase('app-sources','PBXSourcesBuildPhase',source_builds),phase('app-frameworks','PBXFrameworksBuildPhase',[]),phase('app-resources','PBXResourcesBuildPhase',resources)]
test_phases=[phase('test-sources','PBXSourcesBuildPhase',test_builds),phase('test-frameworks','PBXFrameworksBuildPhase',[]),phase('test-resources','PBXResourcesBuildPhase',[])]
project_configs=config_list('project',{'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym','SWIFT_STRICT_CONCURRENCY':'targeted'})
app_configs=config_list('app',{'PRODUCT_BUNDLE_IDENTIFIER':'com.wenjin.cichu','PRODUCT_NAME':'$(TARGET_NAME)','INFOPLIST_FILE':'Cichu/Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'1.0','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']})
test_configs=config_list('tests',{'PRODUCT_BUNDLE_IDENTIFIER':'com.wenjin.cichu.tests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Cichu.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Cichu','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks']})
app_target=add('app-target','PBXNativeTarget',buildConfigurationList=app_configs,buildPhases=app_phases,buildRules=[],dependencies=[],name='Cichu',productName='Cichu',productReference=app_product,productType='com.apple.product-type.application')
proxy=add('test-proxy','PBXContainerItemProxy',containerPortal=oid('project'),proxyType=1,remoteGlobalIDString=app_target,remoteInfo='Cichu')
dependency=add('test-dependency','PBXTargetDependency',target=app_target,targetProxy=proxy)
test_target=add('test-target','PBXNativeTarget',buildConfigurationList=test_configs,buildPhases=test_phases,buildRules=[],dependencies=[dependency],name='CichuTests',productName='CichuTests',productReference=test_product,productType='com.apple.product-type.bundle.unit-test')
project=add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600','TargetAttributes':{app_target:{'CreatedOnToolsVersion':'16.0'},test_target:{'CreatedOnToolsVersion':'16.0','TestTargetID':app_target}}},buildConfigurationList=project_configs,compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['zh-Hans','en','Base'],mainGroup=main_group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app_target,test_target])
def serialize(value, indent=0):
    tab='\t'*indent
    if isinstance(value,dict): return '{\n'+''.join('\t'*(indent+1)+json.dumps(k)+' = '+serialize(v,indent+1)+';\n' for k,v in value.items())+tab+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(indent+1)+serialize(v,indent+1)+',\n' for v in value)+tab+')'
    if isinstance(value,int): return str(value)
    return json.dumps(value,ensure_ascii=False)
project_dir=ROOT/'Cichu.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
schemes=project_dir/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
def reference(identifier,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Cichu.xcodeproj"/>'
(schemes/'Cichu.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app_target,'Cichu.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(test_target,'CichuTests.xctest')}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app_target,'Cichu.app')}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app_target,'Cichu.app')}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated project with {len(source_builds)} Swift source files and {len(test_builds)} test files. No build executed.')
