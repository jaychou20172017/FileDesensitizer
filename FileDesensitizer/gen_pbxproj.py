#!/usr/bin/env python3
"""Generate project.pbxproj for FileDesensitizer Xcode project.
Dynamically scans all .swift files in the project directory."""

import uuid, os, hashlib

BASE = "/Users/jiezhou/个人/AI/文件脱敏软件/FileDesensitizer"
PROJ_DIR = os.path.join(BASE, "FileDesensitizer.xcodeproj")
SRC_DIR = os.path.join(BASE, "FileDesensitizer")

def uid(seed):
    """Deterministic UUID from seed string."""
    h = hashlib.sha256(seed.encode()).hexdigest()[:24].upper()
    return h

# Structural UUIDs (deterministic from their names)
ids = {}
for key in [
    "project", "mainGroup", "appGroup", "productsGroup",
    "viewsGroup", "viewModelsGroup", "servicesGroup", "modelsGroup", "utilitiesGroup",
    "target", "productRef",
    "sourcesPhase", "frameworksPhase",
    "projectConfigList", "targetConfigList",
    "debugProject", "releaseProject", "debugTarget", "releaseTarget",
    "spmPackage", "spmProduct"
]:
    ids[key] = uid(key)

# Discover all Swift source files
swift_files = []
for root, dirs, files in os.walk(SRC_DIR):
    for f in files:
        if f.endswith(".swift"):
            full = os.path.join(root, f)
            rel = os.path.relpath(full, SRC_DIR)
            swift_files.append(rel)

swift_files.sort()
print(f"Found {len(swift_files)} Swift files:")
for f in swift_files:
    print(f"  {f}")

# Generate file reference and build file UUIDs
file_refs = {}   # rel_path -> ref UUID
file_builds = {} # rel_path -> build UUID
for f in swift_files:
    file_refs[f] = uid(f"ref:{f}")
    file_builds[f] = uid(f"build:{f}")

# --- Build PBXBuildFile section ---
build_files_section = ""
for f in swift_files:
    build_files_section += f'\t\t{file_builds[f]} /* {os.path.basename(f)} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[f]} /* {os.path.basename(f)} */; }};\n'

# --- Build PBXFileReference section ---
file_ref_section = ""
for f in swift_files:
    file_ref_section += f'\t\t{file_refs[f]} /* {os.path.basename(f)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {os.path.basename(f)}; sourceTree = "<group>"; }};\n'
# Add product reference
file_ref_section += f'\t\t{ids["productRef"]} /* FileDesensitizer.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FileDesensitizer.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n'

# --- Build group children ---
# Group files by directory
root_files = [f for f in swift_files if "/" not in f]
views_files = [f for f in swift_files if f.startswith("Views/")]
viewmodels_files = [f for f in swift_files if f.startswith("ViewModels/")]
services_files = [f for f in swift_files if f.startswith("Services/")]
models_files = [f for f in swift_files if f.startswith("Models/")]
utilities_files = [f for f in swift_files if f.startswith("Utilities/")]

def group_children(files):
    """Generate group children entries for a set of file paths."""
    refs = [f'{file_refs[f]} /* {os.path.basename(f)} */' for f in files]
    return ",\n\t\t\t\t".join(refs)

app_children = []
for f in root_files:
    app_children.append(f'{file_refs[f]} /* {os.path.basename(f)} */')
# Add subgroup references
if views_files:
    app_children.append(f'{ids["viewsGroup"]} /* Views */')
if viewmodels_files:
    app_children.append(f'{ids["viewModelsGroup"]} /* ViewModels */')
if services_files:
    app_children.append(f'{ids["servicesGroup"]} /* Services */')
if models_files:
    app_children.append(f'{ids["modelsGroup"]} /* Models */')
if utilities_files:
    app_children.append(f'{ids["utilitiesGroup"]} /* Utilities */')

app_children_str = ",\n\t\t\t\t".join(app_children)

# Group children for subgroups
views_children = group_children(views_files)
vms_children = group_children(viewmodels_files)
svc_children = group_children(services_files)
mod_children = group_children(models_files)
util_children = group_children(utilities_files)

# --- Build sources build phase files ---
sources_files = ""
for f in swift_files:
    sources_files += f'\t\t\t\t{file_builds[f]} /* {os.path.basename(f)} in Sources */,\n'

# --- Group sections (only include non-empty groups) ---
def group_section(uid, name, path, children_str):
    if not children_str.strip():
        return ""
    return f'''\t\t{uid} /* {name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{children_str}
\t\t\t);
\t\t\tpath = {path};
\t\t\tsourceTree = "<group>";
\t\t}};'''

# Only include subgroups that have files
views_group_block = group_section(ids["viewsGroup"], "Views", "Views", views_children)
vms_group_block = group_section(ids["viewModelsGroup"], "ViewModels", "ViewModels", vms_children)
svc_group_block = group_section(ids["servicesGroup"], "Services", "Services", svc_children)
mod_group_block = group_section(ids["modelsGroup"], "Models", "Models", mod_children)
util_group_block = group_section(ids["utilitiesGroup"], "Utilities", "Utilities", util_children)

subgroups_blocks = views_group_block + vms_group_block + svc_group_block + mod_group_block + util_group_block

pbxproj = f'''// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{build_files_section}/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_ref_section}/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{ids["frameworksPhase"]} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{ids["mainGroup"]} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ids["appGroup"]} /* FileDesensitizer */,
\t\t\t\t{ids["productsGroup"]} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ids["appGroup"]} /* FileDesensitizer */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_children_str}
\t\t\t);
\t\t\tpath = FileDesensitizer;
\t\t\tsourceTree = "<group>";
\t\t}};
{subgroups_blocks}
\t\t{ids["productsGroup"]} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ids["productRef"]} /* FileDesensitizer.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{ids["target"]} /* FileDesensitizer */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ids["targetConfigList"]};
\t\t\tbuildPhases = (
\t\t\t\t{ids["sourcesPhase"]} /* Sources */,
\t\t\t\t{ids["frameworksPhase"]} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = FileDesensitizer;
\t\t\tpackageProductDependencies = (
\t\t\t\t{ids["spmProduct"]} /* CoreXLSX */,
\t\t\t);
\t\t\tproductName = FileDesensitizer;
\t\t\tproductReference = {ids["productRef"]};
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{ids["project"]} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2600;
\t\t\t\tLastUpgradeCheck = 2600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{ids["target"]} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {ids["projectConfigList"]};
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t\t"zh-Hans",
\t\t\t);
\t\t\tmainGroup = {ids["mainGroup"]};
\t\t\tpackageReferences = (
\t\t\t\t{ids["spmPackage"]} /* XCRemoteSwiftPackageReference "CoreXLSX" */,
\t\t\t);
\t\t\tproductRefGroup = {ids["productsGroup"]};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{ids["target"]} /* FileDesensitizer */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
\t\t{ids["sourcesPhase"]} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{sources_files}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{ids["debugProject"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ids["releaseProject"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = s;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{ids["debugTarget"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.filedesensitizer.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ids["releaseTarget"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.filedesensitizer.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{ids["projectConfigList"]} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ids["debugProject"]} /* Debug */,
\t\t\t\t{ids["releaseProject"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{ids["targetConfigList"]} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ids["debugTarget"]} /* Debug */,
\t\t\t\t{ids["releaseTarget"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
\t\t{ids["spmPackage"]} /* XCRemoteSwiftPackageReference "CoreXLSX" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/CoreOffice/CoreXLSX";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 0.14.0;
\t\t\t}};
\t\t}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{ids["spmProduct"]} /* CoreXLSX */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {ids["spmPackage"]};
\t\t\tproductName = CoreXLSX;
\t\t}};
/* End XCSwiftPackageProductDependency section */

\t}};
\trootObject = {ids["project"]} /* Project object */;
}}
'''

os.makedirs(PROJ_DIR, exist_ok=True)
with open(os.path.join(PROJ_DIR, "project.pbxproj"), "w") as f:
    f.write(pbxproj)

print("\nproject.pbxproj generated successfully!")
