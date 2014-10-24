/*
 * Copyright 2014 Domabo; Portions Copyright 2014 Red Hat
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

"use strict";

var util = require('util');
var Stream = require('stream');

function TCP(tcp) {
    if (tcp != null)
    {
        this._tcp = tcp;
    } else {
        this._tcp = io.nodekit.tcp.createSocket();
    }
    
    // Server
    this._tcp.on( "connection", TCP.prototype._onConnection.bind(this) );
    
    //Client
    this._tcp.on( "afterConnect",    TCP.prototype._onAfterConnect.bind(this) );
    
    Stream.call( this, this._tcp );
    
}

util.inherits(TCP, Stream);

Object.defineProperty( TCP.prototype, '_fd', {
                      get: function() {
                      return this._tcp.fd;
                      }
})


// ----------------------------------------
// Server
// ----------------------------------------
TCP.prototype._onConnection = function(result) {
    var err;
    var clientHandle = new TCP( result.result );
    this.onconnection(err, clientHandle);
}

// ----------------------------------------
// Client
// ----------------------------------------

TCP.prototype._onAfterConnect = function(result) {
    var status = 0;
    var handle = this;
    var readable = true;
    var writable = true;;
    
    if ( this._req ) {
        var oncomplete = this._req.oncomplete;
        delete this._req.oncomplete;
        oncomplete( status, handle, this._req, readable, writable );
    }
}

// ----------------------------------------

TCP.prototype.getpeername = function(out) {
    var remote = this._tcp.remoteAddress;
    out.address = remote.address.hostAddress;
    out.port    = remote.port;
    out.family  = 'IPv4';
}

TCP.prototype.getsockname = function(out) {
    var local = this._tcp.localAddress;
    out.address = local.address.hostAddress;
    out.port    = local.port;
    out.family  ='IPv4';
}

TCP.prototype.bind6 = function(addr,port) {
    return new Error( "ipv6 not supported" );
}

TCP.prototype.bind = function(addr, port) {
    this._tcp.bind( addr, port);
}

TCP.prototype.listen = function(backlog) {
    this._tcp.listen(backlog);
}

TCP.prototype.connect = function(req, addr, port) {
    this._req = req;
    this._tcp.connect(addr,port);
}

module.exports.TCP = TCP;