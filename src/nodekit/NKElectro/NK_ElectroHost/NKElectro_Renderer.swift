/*
* nodekit.io
*
* Copyright (c) 2016 OffGrid Networks. All Rights Reserved.
* Portions Copyright (c) 2013 GitHub, Inc. under MIT License
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

#if !COCOAPODS
    import NKScripting
#endif

extension NKElectro {

    static func bootToRenderer(context: NKScriptContext) {
        
        let appjs = NKStorage.getResource("lib-electro/_nke_renderer", NKElectro.self)
        
        let script = "function loadbootstrap(){\n" + appjs! + "\n}\n" + "loadbootstrap();" + "\n"
        
        context.NKinjectJavaScript(NKScriptSource(source: script, asFilename: "io.nodekit.electro/lib-electro/_nke_renderer.js", namespace: "io.nodekit.electro.renderer"))

        NKE_IpcRenderer.attachTo(context)

    }
}
