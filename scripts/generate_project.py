"""Generate a deterministic Xcode project without third-party dependencies."""
from pathlib import Path
import hashlib
import plistlib

ROOT=Path(__file__).resolve().parents[1]
def ident(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def generate():
    sources=sorted(p.relative_to(ROOT).as_posix() for base in ['Sources','PicktApp'] for p in (ROOT/base).rglob('*.swift'))
    objects=[]
    def obj(key,body): objects.append(f'{ident(key)} = {{ {body} }};');return ident(key)
    refs=[];builds=[]
    for path in sources:
        ref=obj(path,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = "<group>";')
        refs.append(ref);builds.append(obj('build'+path,f'isa = PBXBuildFile; fileRef = {ref};'))
    product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = Pickt.app; sourceTree = BUILT_PRODUCTS_DIR;')
    products=obj('products',f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
    group=obj('group',f'isa = PBXGroup; children = ({",".join(refs+[products])},); sourceTree = "<group>";')
    phase=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
    resources=obj('resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    configs=[]
    for name in ['Debug','Release']:
        settings='IPHONEOS_DEPLOYMENT_TARGET = 15.5; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; PRODUCT_NAME = Pickt; PRODUCT_BUNDLE_IDENTIFIER = com.wenna.pickt; INFOPLIST_FILE = PicktApp/Info.plist; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1; CODE_SIGN_STYLE = Automatic;'
        settings+=' SWIFT_OPTIMIZATION_LEVEL = '+('"-Onone";' if name=='Debug' else '"-O";')
        configs.append(obj('config'+name,f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {name};'))
    configlist=obj('configlist',f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {configlist}; buildPhases = ({phase},{resources},); buildRules = (); dependencies = (); name = Pickt; productName = Pickt; productReference = {product}; productType = "com.apple.product-type.application";')
    project=obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1640; }}; buildConfigurationList = {configlist}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en,Base,zh_CN); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
    folder=ROOT/'Pickt.xcodeproj';folder.mkdir(exist_ok=True)
    (folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}\n',encoding='utf-8')
    schemes=folder/'xcshareddata'/'xcschemes';schemes.mkdir(parents=True,exist_ok=True)
    (schemes/'Pickt.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Pickt.app" BlueprintName="Pickt" ReferencedContainer="container:Pickt.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''',encoding='utf-8')
    print(f'Generated project with {len(sources)} Swift files')
if __name__=='__main__': generate()
