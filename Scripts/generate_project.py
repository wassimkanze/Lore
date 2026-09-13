"""Regenerate the dependency-free Xcode project after adding source files."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parents[1]
objects = {}
signing_path = root/'Config/Signing.local.json'
signing = json.loads(signing_path.read_text()) if signing_path.exists() else {}
if signing:
    identity, team = signing.get('identity', '-'), signing.get('team', '')
    if not re.fullmatch(r'[A-Fa-f0-9]{40}|-', identity) or not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Local signing requires an identity SHA-1 and a 10-character team ID')
    (root/'Config/Signing.local.xcconfig').write_text('LORE_CODE_SIGN_IDENTITY = '+identity+'\nLORE_DEVELOPMENT_TEAM = '+team+'\n')
signing_settings = {'CODE_SIGN_IDENTITY': '$(LORE_CODE_SIGN_IDENTITY)', 'CODE_SIGN_STYLE':'Manual', 'DEVELOPMENT_TEAM':'$(LORE_DEVELOPMENT_TEAM)', 'OTHER_CODE_SIGN_FLAGS':'--timestamp=none'}
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def put(name, body):
    key=ident(name); objects[key]=body; return key
def q(value): return '"'+str(value).replace('\\','\\\\').replace('"','\\"')+'"'
def seq(values): return '('+', '.join(values)+',)' if values else '()'

app_sources=sorted((root/'Lore').rglob('*.swift'))
test_sources=sorted((root/'LoreTests').glob('*.swift'))
signing_ref=put('signingConfig','{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/Signing.xcconfig; sourceTree = SOURCE_ROOT;}')
file_refs=[signing_ref]
def sources(files, scope):
    builds=[]
    for path in files:
        rel=path.relative_to(root).as_posix()
        ref=put('file:'+rel, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+q(rel)+'; sourceTree = SOURCE_ROOT;}')
        if ref not in file_refs: file_refs.append(ref)
        builds.append(put('build:'+scope+':'+rel, '{isa = PBXBuildFile; fileRef = '+ref+';}'))
    return put(scope+'Sources', '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+seq(builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
app_phase=sources(app_sources,'app')
test_phase=sources(test_sources,'test')
shared_power=['PowerHelperProtocol.swift','SignedIdentity.swift','ClosedLidLeaseEngine.swift','ClosedLidEnvironment.swift']
helper_sources=sorted((root/'Helper').glob('*.swift'))+[root/'Lore/Core/Power'/name for name in shared_power]
helper_phase=sources(helper_sources,'helper')
assets=put('assets','{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Lore/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;}')
file_refs.append(assets)
assets_build=put('assetsBuild','{isa = PBXBuildFile; fileRef = '+assets+';}')
app_resources=put('appResources','{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+seq([assets_build])+'; runOnlyForDeploymentPostprocessing = 0;}')
fixture=put('fixtures','{isa = PBXFileReference; lastKnownFileType = folder; path = LoreTests/Fixtures; sourceTree = SOURCE_ROOT;}')
file_refs.append(fixture)
fixture_build=put('fixturesBuild','{isa = PBXBuildFile; fileRef = '+fixture+';}')
test_resources=put('testResources','{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+seq([fixture_build])+'; runOnlyForDeploymentPostprocessing = 0;}')
app_product=put('appProduct','{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Lore.app; sourceTree = BUILT_PRODUCTS_DIR;}')
test_product=put('testProduct','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LoreTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
helper_product=put('helperProduct','{isa = PBXFileReference; explicitFileType = compiled.mach-o.executable; includeInIndex = 0; path = LorePowerHelper; sourceTree = BUILT_PRODUCTS_DIR;}')
helper_plist=put('helperPlist','{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Helper/app.lore.power-helper.plist; sourceTree = SOURCE_ROOT;}')
file_refs.append(helper_plist)
helper_copy=put('helperCopyFile','{isa = PBXBuildFile; fileRef = '+helper_product+'; settings = {ATTRIBUTES = (CodeSignOnCopy,);};}')
helper_plist_copy=put('helperPlistCopyFile','{isa = PBXBuildFile; fileRef = '+helper_plist+';}')
embed_helper=put('embedHelper','{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = Contents/Library/HelperTools; dstSubfolderSpec = 1; files = '+seq([helper_copy])+'; name = "Embed Power Helper"; runOnlyForDeploymentPostprocessing = 0;}')
embed_plist=put('embedHelperPlist','{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = Contents/Library/LaunchDaemons; dstSubfolderSpec = 1; files = '+seq([helper_plist_copy])+'; name = "Embed Power Service"; runOnlyForDeploymentPostprocessing = 0;}')
products=put('products','{isa = PBXGroup; children = '+seq([app_product,test_product,helper_product])+'; name = Products; sourceTree = "<group>";}')
main=put('main','{isa = PBXGroup; children = '+seq(file_refs+[products])+'; sourceTree = "<group>";}')

def configs(scope, extras):
    configs=[]
    for name in ['Debug','Release']:
        settings={'ARCHS':'arm64','MACOSX_DEPLOYMENT_TARGET':'15.0','SDKROOT':'macosx','SWIFT_VERSION':'6.0','CLANG_ENABLE_MODULES':'YES',
                  'SWIFT_STRICT_CONCURRENCY':'complete','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O',
                  'DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym','ENABLE_TESTABILITY':'YES' if name=='Debug' else 'NO',
                  'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if name=='Debug' else '', **extras, **signing_settings, 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS':'YES' if name=='Debug' and scope!='helper' else 'NO'}
        settings=' '.join(k+' = '+q(v)+';' for k,v in settings.items())
        configs.append(put(scope+name,'{isa = XCBuildConfiguration; baseConfigurationReference = '+signing_ref+'; buildSettings = {'+settings+'}; name = '+name+';}'))
    return put(scope+'ConfigList','{isa = XCConfigurationList; buildConfigurations = '+seq(configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
project_configs=configs('project',{})
app_configs=configs('app',{'PRODUCT_BUNDLE_IDENTIFIER':'app.lore.mac','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES',
                          'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','INFOPLIST_KEY_CFBundleDisplayName':'Lore','INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.developer-tools',
                          'MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'1','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Automatic',
                          'ENABLE_APP_SANDBOX':'NO','ENABLE_HARDENED_RUNTIME':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks'})
test_configs=configs('test',{'PRODUCT_BUNDLE_IDENTIFIER':'app.lore.mac.tests','PRODUCT_NAME':'$(TARGET_NAME)',
                            'GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Automatic',
                            'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Lore.app/Contents/MacOS/Lore','BUNDLE_LOADER':'$(TEST_HOST)'})
helper_configs=configs('helper',{'PRODUCT_NAME':'LorePowerHelper','PRODUCT_BUNDLE_IDENTIFIER':'app.lore.power-helper','INFOPLIST_FILE':'Helper/Info.plist','CREATE_INFOPLIST_SECTION_IN_BINARY':'YES','ENABLE_HARDENED_RUNTIME':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'','OTHER_SWIFT_FLAGS':'-parse-as-library'})
helper_target=put('helperTarget','{isa = PBXNativeTarget; buildConfigurationList = '+helper_configs+'; buildPhases = '+seq([helper_phase])+'; buildRules = (); dependencies = (); name = LorePowerHelper; productName = LorePowerHelper; productReference = '+helper_product+'; productType = "com.apple.product-type.tool";}')
helper_proxy=put('helperProxy','{isa = PBXContainerItemProxy; containerPortal = '+ident('project')+'; proxyType = 1; remoteGlobalIDString = '+helper_target+'; remoteInfo = LorePowerHelper;}')
helper_dep=put('helperDependency','{isa = PBXTargetDependency; target = '+helper_target+'; targetProxy = '+helper_proxy+';}')
app_target=put('appTarget','{isa = PBXNativeTarget; buildConfigurationList = '+app_configs+'; buildPhases = '+seq([app_phase,app_resources,embed_helper,embed_plist])+'; buildRules = (); dependencies = '+seq([helper_dep])+'; name = Lore; productName = Lore; productReference = '+app_product+'; productType = "com.apple.product-type.application";}')
proxy=put('proxy','{isa = PBXContainerItemProxy; containerPortal = '+ident('project')+'; proxyType = 1; remoteGlobalIDString = '+app_target+'; remoteInfo = Lore;}')
dep=put('testDependency','{isa = PBXTargetDependency; target = '+app_target+'; targetProxy = '+proxy+';}')
test_target=put('testTarget','{isa = PBXNativeTarget; buildConfigurationList = '+test_configs+'; buildPhases = '+seq([test_phase,test_resources])+'; buildRules = (); dependencies = '+seq([dep])+'; name = LoreTests; productName = LoreTests; productReference = '+test_product+'; productType = "com.apple.product-type.bundle.unit-test";}')
project=put('project','{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600;}; buildConfigurationList = '+project_configs+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = '+main+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+seq([app_target,test_target,helper_target])+';}')
(root/'Lore.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(key+' = '+body+';' for key,body in objects.items())+'\n}; rootObject = '+project+';}\n')
def ref(target,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Lore.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app_target,'Lore.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test_target,'LoreTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_target,'Lore.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_target,'Lore.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root/'Lore.xcodeproj/xcshareddata/xcschemes/Lore.xcscheme').write_text(scheme)
print(f'Generated Xcode project: {len(app_sources)} app sources, {len(test_sources)} test sources')
