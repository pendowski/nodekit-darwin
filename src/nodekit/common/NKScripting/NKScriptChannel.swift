/*
* nodekit.io
*
* Copyright (c) 2016 OffGrid Networks. All Rights Reserved.
* Portions Copyright 2015 XWebView
* Portions Copyright (c) 2014 Intel Corporation.  All rights reserved.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*      http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import Foundation

public class NKScriptChannel : NSObject, NKScriptMessageHandler {
    private(set) public var identifier: String?
    public let thread: NSThread?
    public let queue: dispatch_queue_t?
    private(set) public weak var context: NKScriptContext?
    internal weak var userContentController: NKScriptContentController?
    private var isFactory = false;
    
    var typeInfo: NKScriptMetaObject!

    private var instances = [Int: NKScriptValueObjectNative]()
    private var userScript: AnyObject?
    private(set) var principal: NKScriptValueObjectNative {
        get { return instances[0]! }
        set { instances[0] = newValue }
    }

    private class var sequenceNumber: Int {
        struct sequence{
            static var number: Int = 0
        }
        return ++sequence.number
    }
    
    internal var nativeFirstSequence: Int {
        struct sequence{
            static var number: Int = Int(Int32.max)
            
        }
        return --sequence.number
    }

    internal static var defaultQueue: dispatch_queue_t = {
        let label = "io.nodekit.scripting.default-queue"
        return dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL)
    }()

    public convenience init(context: NKScriptContext) {
        self.init(context: context, queue: NKScriptChannel.defaultQueue)
    }

    public init(context: NKScriptContext, queue: dispatch_queue_t) {
        self.context = context
        self.queue = queue
        thread = nil
        super.init()
        self.prepareForPlugin()
    }

    public init(context: NKScriptContext, thread: NSThread) {
        self.context = context
        self.thread = thread
        queue = nil
        super.init()
        self.prepareForPlugin()
    }
    
    deinit {
        guard let id = identifier else {return}
        log("channel deinit" + id);
    }
    
    public static func currentContext() -> NKScriptContext! {
        return NSThread.currentThread().threadDictionary.objectForKey("nk.CurrentContext") as? NKScriptContext
    }
    
    private func prepareForPlugin() {
        let key = unsafeAddressOf(NKScriptChannel)
        if objc_getAssociatedObject(context, key) != nil { return }
        
        let bundle = NSBundle(forClass: NKScriptChannel.self)
        guard let path = bundle.pathForResource("nkscripting", ofType: "js"),
            let source = try? NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding) else {
                die("Failed to read provision script: nkscripting")
        }
        
        let nkscript = context!.NKinjectJavaScript(NKScriptSource(source: source as String, asFilename: "io.nodekit/scripting/nkscripting.js", namespace: "NKScripting"))
        objc_setAssociatedObject(context, key, nkscript, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        let key2 = unsafeAddressOf(NKScriptInvocation)
        guard let path2 = bundle.pathForResource("promise", ofType: "js"),
            let source2 = try? NSString(contentsOfFile: path2, encoding: NSUTF8StringEncoding) else {
                die("Failed to read provision script: nkscripting")
        }
        
        let nkpromise = context!.NKinjectJavaScript(NKScriptSource(source: source2 as String, asFilename: "io.nodekit/scripting/promise", namespace: "Promise"))
        objc_setAssociatedObject(context, key2, nkpromise, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        log("E\(context!.NKid) JavaScript Engine is ready for loading plugins")
    }

    public func bindPlugin(object: AnyObject, toNamespace namespace: String) -> NKScriptValueObject? {
        guard identifier == nil, let context = context else { return nil }

        let id = (object as? NKScriptExport)?.channelIdentifier ?? String(NKScriptChannel.sequenceNumber)
        identifier = id
        userContentController?.NKaddScriptMessageHandler(self, name: id)
        
        if (object is AnyClass)
        {
            isFactory = true;
            typeInfo = NKScriptMetaObject(plugin: object as! AnyClass)
            objc_setAssociatedObject(typeInfo.plugin, unsafeAddressOf(NKScriptChannel), self, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        } else
        {
            isFactory = false;
            typeInfo = NKScriptMetaObject(plugin: object.dynamicType)
        }
        
         principal = NKScriptValueObjectNative(namespace: namespace, channel: self, object: object)
        
         userScript = context.NKinjectJavaScript(NKScriptSource(source: generateStubs(_stdlib_getDemangledTypeName(object)), asFilename: "io.nodekit.scripting/plugins/" + _stdlib_getDemangledTypeName(object) + ".js" ))
        
        log("+E\(context.NKid) Plugin object \(object) is bound to \(namespace) with channel \(id)")
        return principal as NKScriptValueObject
    }
    
    public func unbind() {
        
        guard let id = identifier else { return }
        log("channel unbind" + id);
        
        let namespace = principal.namespace
        let plugin = principal.plugin
        log("+unbinding Plugin object \(plugin) from \(namespace)")
        instances.removeAll(keepCapacity: false)
        userContentController?.NKremoveScriptMessageHandlerForName(id)
        userScript = nil
        identifier = nil
        log("+Plugin object \(plugin) is unbound from \(namespace)")
    }

    public func userContentController(didReceiveScriptMessage message: NKScriptMessage) {
        // A workaround for crash when postMessage(undefined)
        guard unsafeBitCast(message.body, COpaquePointer.self) != nil else { return }
        NSThread.currentThread().threadDictionary.setObject(self.context!, forKey: "nk.CurrentContext")
        if let body = message.body as? [String: AnyObject], let opcode = body["$opcode"] as? String {
            let target = (body["$target"] as? NSNumber)?.integerValue ?? 0
            if let object = instances[target] {
                if opcode == "-" {
                    if target == 0 {
                        // Dispose plugin
                        unbind()
                    } else if let instance = instances.removeValueForKey(target) {
                        // Dispose instance
                        log("+E\(context!.NKid) Instance \(target) is unbound from \(instance.namespace)")
                    } else {
                        log("?Invalid instance id: \(target)")
                    }
                } else if let member = typeInfo[opcode] where member.isProperty {
                    // Update property
                    object.updateNativeProperty(opcode, withValue: body["$operand"] ?? NSNull())
                } else if let member = typeInfo[opcode] where member.isMethod {
                    // Invoke method
                    if let args = (body["$operand"] ?? []) as? [AnyObject] {
                        object.invokeNativeMethod(opcode, withArguments: args)
                    } // else malformatted operand
                } else {
                    log("?Invalid member name: \(opcode)")
                }
            } else if opcode == "+" {
                // Create instance
                let args = body["$operand"] as? [AnyObject]
                let namespace = "\(principal.namespace)[\(target)]"
                instances[target] = NKScriptValueObjectNative(namespace: namespace, channel: self, arguments: args)
                log("+E\(context!.NKid) Instance \(target) is bound to \(namespace)")
            } // else Unknown opcode
        } else if let obj = principal.plugin as? NKScriptMessageHandler {
            // Plugin claims for raw messages
            obj.userContentController(didReceiveScriptMessage: message)
        } else {
            // discard unknown message
            log("-Unknown message: \(message.body)")
        }
        NSThread.currentThread().threadDictionary.removeObjectForKey( "nk.CurrentContext")
        
    }
    
    public func userContentControllerSync(didReceiveScriptMessage message: NKScriptMessage) -> AnyObject! {
        NSThread.currentThread().threadDictionary.setObject(self.context!, forKey: "nk.CurrentContext")
        var result: AnyObject!
        if let body = message.body as? [String: AnyObject], let opcode = body["$opcode"] as? String {
            let target = (body["$target"] as? NSNumber)?.integerValue ?? 0
            if let object = instances[target] {
                if opcode == "-" {
                    if target == 0 {
                        // Dispose plugin
                        unbind()
                        result = true;
                    } else if let instance = instances.removeValueForKey(target) {
                        // Dispose instance
                        log("+E\(context!.NKid) Instance \(target) is unbound from \(instance.namespace)")
                        result = true;
                    } else {
                        log("?Invalid instance id: \(target)")
                        result = true;
                    }
                } else if let member = typeInfo[opcode] where member.isProperty {
                    // Update property
                    object.updateNativeProperty(opcode, withValue: body["$operand"] ?? NSNull())
                    result = true;
                } else if let member = typeInfo[opcode] where member.isMethod {
                    // Invoke method
                    if let args = (body["$operand"] ?? []) as? [AnyObject] {
                       result = object.invokeNativeMethodSync(opcode, withArguments: args)
                    } // else malformatted operand
                } else {
                    log("?Invalid member name: \(opcode)")
                      result = false;
                }
            } else if opcode == "+" {
                // Create instance
                let args = body["$operand"] as? [AnyObject]
                let namespace = "\(principal.namespace)[\(target)]"
                instances[target] = NKScriptValueObjectNative(namespace: namespace, channel: self, arguments: args)
                log("+E\(context!.NKid) Instance \(target) is bound to \(namespace)")
                result = true;
            } // else Unknown opcode
        } else if let obj = principal.plugin as? NKScriptMessageHandler {
            // Plugin claims for raw messages
            result = obj.userContentControllerSync(didReceiveScriptMessage: message)
      } else {
            // discard unknown message
            log("-Unknown message: \(message.body)")
            result = false;
        }
        NSThread.currentThread().threadDictionary.removeObjectForKey( "nk.CurrentContext")
        return result;
    }
    
    private func generateStubs(name: String) -> String {
        func generateMethod(key: String, this: String, prebind: Bool) -> String {
            let stub = "NKScripting.invokeNative.bind(\(this), '\(key)')"
            return prebind ? "\(stub);" : "function(){return \(stub).apply(null, arguments);}"
        }
        func rewriteStub(stub: String, forKey key: String) -> String {
            return (principal.plugin as? NKScriptExport)?.rewriteGeneratedStub?(stub, forKey: key) ?? stub
        }

        let prebind = !(typeInfo[""]?.isInitializer ?? false)
        let stubs = typeInfo.reduce("") {
            let key = $1.0
            let member = $1.1
            let stub: String
            if member.isMethod && !key.isEmpty {
                let method = generateMethod("\(key)\(member.type)", this: prebind ? "exports" : "this", prebind: prebind)
                stub = "exports.\(key) = \(method)"
            } else if member.isProperty {
                if (isFactory) {  stub = "NKScripting.defineProperty(exports, '\(key)', null, \(member.setter != nil));" }
                else {
                    let value = principal.serialize(principal[key])
                    stub = "NKScripting.defineProperty(exports, '\(key)', \(value), \(member.setter != nil));"
                }
            } else {
                return $0
            }
            return $0 + rewriteStub(stub, forKey: key) + "\n"
        }

        let base: String
        if let member = typeInfo[""] {
            if member.isInitializer {
                base = "'\(member.type)'"
            } else {
                base = generateMethod("\(member.type)", this: "arguments.callee", prebind: false)
            }
        } else {
            base = rewriteStub("null", forKey: ".base")
        }

        return rewriteStub(
            "(function(exports) {\n" +
                rewriteStub(stubs, forKey: ".local") +
                "})(NKScripting.createPlugin('\(identifier!)', '\(principal.namespace)', \(base)));\n" /* + rewriteStub("\n//# sourceURL=io.nodekit.scripting/plugins/\(name).js", forKey: ".sourceURL") */,
            forKey: ".global"
        )
    }
}
