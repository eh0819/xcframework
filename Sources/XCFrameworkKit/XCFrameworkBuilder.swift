//
//  XCFrameworkBuilder.swift
//  XCFrameworkKit
//
//  Created by Jeff Lett on 6/8/19.
//

import Foundation
import Shell

public class XCFrameworkBuilder {
    public var name: String?
    public var project: String?
    public var outputDirectory: String?
    public var buildDirectory: String?
    public var iOSScheme: String?
    public var watchOSScheme: String?
    public var tvOSScheme: String?
    public var allScheme: String?
    public var verbose: Bool = false
    public var compilerArguments: [String]?
    
    public enum XCFrameworkError: Error {
        case nameNotFound
        case projectNotFound
        case noSchemesFound
        case buildDirectoryNotFound
        case outputDirectoryNotFound
        case buildError(String)
        
        public var description: String {
            switch self {
            case .nameNotFound:
                return "No name parameter found."
            case .projectNotFound:
                return "No project parameter found."
            case .noSchemesFound:
                return "No schemes found."
            case .buildDirectoryNotFound:
                return "No build directory found."
            case .outputDirectoryNotFound:
                return "No output directory found."
            case .buildError(let stderr):
                return stderr
            }
        }
    }
    
    private enum SDK: String {
        case iOS = "iphoneos"
        case watchOS = "watchos"
        case tvOS = "appletvos"
        case macOS = "macosx"
        case iOSSim = "iphonesimulator"
        case watchOSSim = "watchsimulator"
        case tvOSSim = "appletvsimulator"
    }
    
    public init(configure: (XCFrameworkBuilder) -> ()) {
        configure(self)
    }
    
    public func build() -> Result<(),XCFrameworkError> {
        
        guard let name = name else {
            return .failure(XCFrameworkError.nameNotFound)
        }
        
        guard let project = project else {
            return .failure(XCFrameworkError.projectNotFound)
        }
        
        guard watchOSScheme != nil || iOSScheme != nil || allScheme != nil || tvOSScheme != nil else {
            return .failure(XCFrameworkError.noSchemesFound)
        }
        
        guard let outputDirectory = outputDirectory else {
            return .failure(XCFrameworkError.outputDirectoryNotFound)
        }
        
        guard let buildDirectory = buildDirectory else {
            return .failure(XCFrameworkError.buildDirectoryNotFound)
        }
        
        print("Creating \(name)...")
        
        //final build location
        let finalBuildDirectory = buildDirectory.hasSuffix("/") ? buildDirectory : buildDirectory + "/"
        
        //final xcframework location
        let finalOutputDirectory = outputDirectory.hasSuffix("/") ? outputDirectory : outputDirectory + "/"
        let finalOutput = finalOutputDirectory + name + ".xcframework"
        
        shell.usr.rm(finalOutput)
        //array of arguments for the final xcframework construction
        var frameworksArguments = ["-create-xcframework"]
        
        //try all supported SDKs
        do {
            
            if let watchOSScheme = watchOSScheme {
                try frameworksArguments.append(contentsOf: buildScheme(scheme: watchOSScheme, sdk: .watchOS, project: project, name: name, buildPath: finalBuildDirectory))
                try frameworksArguments.append(contentsOf: buildScheme(scheme: watchOSScheme, sdk: .watchOSSim, project: project, name: name, buildPath: finalBuildDirectory))
            }
            
            if let iOSScheme = iOSScheme {
                try frameworksArguments.append(contentsOf: buildScheme(scheme: iOSScheme, sdk: .iOS, project: project, name: name, buildPath: finalBuildDirectory))
                try frameworksArguments.append(contentsOf: buildScheme(scheme: iOSScheme, sdk: .iOSSim, project: project, name: name, buildPath: finalBuildDirectory))
            }
            
            if let tvOSScheme = tvOSScheme {
                try frameworksArguments.append(contentsOf: buildScheme(scheme: tvOSScheme, sdk: .tvOS, project: project, name: name, buildPath: finalBuildDirectory))
                try frameworksArguments.append(contentsOf: buildScheme(scheme: tvOSScheme, sdk: .tvOSSim, project: project, name: name, buildPath: finalBuildDirectory))
            }
            
            
            // Modified for Dexcom scheme pattern
            // This will use the xcframework project name as the scheme
            if let allScheme = allScheme {
                
                // Let's split up the different schemes into their corresponding values
                
                let splitSchemes = allScheme.components(separatedBy: ",");
                
                // Get the same of the scheme
                let schemeToUse = ((project as NSString).lastPathComponent).split(separator: ".").map(String.init).first
                
                try splitSchemes.forEach { scheme in
                    
                    if(scheme.trimmingCharacters(in: .whitespacesAndNewlines) == "iOS") {
                        var iosScheme = String(schemeToUse!)
                        iosScheme.append("Production")
                        try frameworksArguments.append(contentsOf: buildScheme(scheme: iosScheme, sdk: .iOS, project: project, name: name, buildPath: finalBuildDirectory))
                    }
                    
                    if(scheme.trimmingCharacters(in: .whitespacesAndNewlines) == "watchOS") {
                        
                        var watchScheme = String(schemeToUse!)
                        watchScheme.append("WatchOS")
                         try frameworksArguments.append(contentsOf: buildScheme(scheme: watchScheme, sdk: .watchOS, project: project, name: name, buildPath: finalBuildDirectory))
                    }
                    
                    
                }
                
               
            }
        } catch let error as XCFrameworkError {
            return .failure(error)
        } catch {
            return .failure(.buildError(error.localizedDescription))
        }
        
        print("Combining...")
        //add output to final command
        frameworksArguments.append("-output")
        frameworksArguments.append(finalOutput)
        if verbose {
            print("xcodebuild \(frameworksArguments.joined(separator: " "))")
        }
        let result = shell.usr.bin.xcodebuild.dynamicallyCall(withArguments: frameworksArguments)
        if !result.isSuccess {
            return .failure(.buildError(result.stderr + "\nXCFramework Build Error From Running: 'xcodebuild \(frameworksArguments.joined(separator: " "))'"))
        }
        print("Success. \(finalOutput)")
        return .success(())
    }
    
    private func buildScheme(scheme: String, sdk: SDK, project: String, name: String, buildPath: String) throws -> [String] {
        print("Building scheme \(scheme) for \(sdk.rawValue)...")
        var frameworkArguments = [String]()
        //path for each scheme's archive
        let archivePath = buildPath + "\(scheme)-\(sdk.rawValue).xcarchive"
        //array of arguments for the archive of each framework
        //weird interpolation errors are forcing me to use this "" + syntax.  not sure if this is a compiler bug or not.
        var archiveArguments = ["-workspace", "\"" + project + "\"", "-scheme", "\"" + scheme + "\"", "archive", "SKIP_INSTALL=NO", "BUILD_LIBRARY_FOR_DISTRIBUTION=YES"]
        if let compilerArguments = compilerArguments {
            archiveArguments.append(contentsOf: compilerArguments)
        }
        archiveArguments.append(contentsOf: ["-archivePath", archivePath, "-sdk", sdk.rawValue])
        if verbose {
            print("   xcodebuild \(archiveArguments.joined(separator: " "))")
        }
        let result = shell.usr.bin.xcodebuild.dynamicallyCall(withArguments: archiveArguments)
        if !result.isSuccess {
            let errorMessage = result.stderr + "\nArchive Error From Running: 'xcodebuild \(archiveArguments.joined(separator: " "))'"
            throw XCFrameworkError.buildError(errorMessage)
        }
        //add this framework to the list for the final output command
        frameworkArguments.append("-framework")
        frameworkArguments.append(archivePath + "/Products/Library/Frameworks/\(name).framework")
        return frameworkArguments
    }
    
}
