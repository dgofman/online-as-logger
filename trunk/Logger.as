package {
	/*
	This library compatible with projects
	http://www.docsultant.com/site2/articles/flex_xpanel.html - XPanel for FLEX/Flash
	https://addons.mozilla.org/en-US/firefox/addon/1843 - Mozilla FireFox (FireBug pluggin)
	http://code.google.com/p/flash-thunderbolt - ThunderBolt AS3 Console
	*/
	
	import flash.display.Sprite;
	import flash.events.StatusEvent;
	import flash.external.ExternalInterface;
	import flash.net.LocalConnection;
	import flash.utils.clearInterval;
	import flash.utils.describeType;
	import flash.utils.getQualifiedClassName;
	import flash.utils.getTimer;
	import flash.utils.setInterval;
	import flash.xml.XMLNode;

	public class Logger extends Sprite
	{
		private var _level:int;
		private var _type:String;
	
		private static var _xpanel_lc:LocalConnection;
		private static var _localConnectionClient:Object;

		private static const xpanelConnectionName:String = "_xpanel1";
		private static const loggerConnectionName:String = "_logger";
		
		public static const LOGGER_DEBUG:Logger       = new Logger(0x01, "log");
		public static const LOGGER_INFORMATION:Logger = new Logger(0x02, "info");
		public static const LOGGER_WARNING:Logger     = new Logger(0x04, "warn");
		public static const LOGGER_ERROR:Logger       = new Logger(0x08, "error");
		
		public static const EXTERNAL_LOG_CHANNEL:int =  0; 
		
		private static const CHAR_LIMIT:uint = 40000; //LocalConnection error: 2084 The AMF encoding of the arguments cannot exceed 40K. 
		private static const ARRAY_DELIMITER:String = "\u00B6";
		
		private static var _js_bridge_initialized:Boolean = false;
		private static var _connectionInterval:Number;
		
		function Logger(level:int=-1, type:String=null){
			if(_js_bridge_initialized == false && ExternalInterface.available){
				ExternalInterface.addCallback("js_trace", js_trace);
				_js_bridge_initialized = true;
			}
			this._level = level;
			this._type = type;
		}
		
		public function get level():int{
			return _level;
		}
		
		public function get type():String{
			return _type;
		}

		public static function alert(o:Object):void{
			ExternalInterface.call("alert", toString(o));
		}
		
		public static function debug(o:Object):void{
			_send(LOGGER_DEBUG, o);
		}

		public static function info(o:Object):void{
			_send(LOGGER_INFORMATION, o);
		}

		public static function error(o:Object):void{
			_send(LOGGER_ERROR, o);
		}

		public static function warn(o:Object):void{
			_send(LOGGER_WARNING, o);
		}

		public static function params(... args):void{
			_send(LOGGER_DEBUG, (args is Array ? args.join(", ") : args));
		}
		
		private function js_trace(type:String="log", o:Object=null):void{
			var loggers:Array = [LOGGER_DEBUG, LOGGER_INFORMATION, LOGGER_WARNING, LOGGER_ERROR];
			for(var i:uint = 0; i < loggers.length; i++){
				if(loggers[i].type == type){
					_send(loggers[i] as Logger, o);
					return;
				}
			}
			ExternalInterface.call("console." + type, formatDate(new Date()) + "  " + o);
		}

		public static function send(channel:uint, ...args):void{
			if(_localConnectionClient == null)
				_localConnectionClient = _connect(-1).client;
			_localConnectionClient.$send(args, channel);
		}

		private static function _send(logger:Logger, o:Object):void{
			try{
				var str:String = (typeof o == "xml" ? o.toXMLString() : toString(o));
				//Send message to Flex Logger
				send(EXTERNAL_LOG_CHANNEL, getTimer(), str, logger.level);
				//Send message to FireBug console
				ExternalInterface.call("console." + logger.type, formatDate(new Date()) + "  " + str);
				//Send message to XPanel
				if(_xpanel_lc == null){
					_xpanel_lc = new LocalConnection();
					_xpanel_lc.allowDomain("*");
				}
				if(str && str.length > CHAR_LIMIT)
					str = str.substring(0, CHAR_LIMIT); 
				_xpanel_lc.addEventListener(StatusEvent.STATUS, function (event:StatusEvent):void{});
				_xpanel_lc.send(xpanelConnectionName, "dispatchMessage", getTimer(), str, logger.level);
			}
			catch (err:Error){
				// ignored.
			}
		}
		
		//Sets response listener. If channel equals to EXTERNAL_LOG_CHANNEL (0), class will received all log messages passed from external application. 
		public static function connect(resultHandler:Function=null, statusHandler:Function=null, channel:uint=EXTERNAL_LOG_CHANNEL):LocalConnection{
			return _connect(channel, resultHandler, statusHandler);
		}
		
		private static function _connect(channel:int, resultHandler:Function=null, statusHandler:Function=null):LocalConnection{
			var message:String;
			var lastStatus:String;
			var lc:LocalConnection = new LocalConnection();
			lc.allowDomain("*");
			lc.client = {$result:resultHandler, $status:statusHandler, $channel:channel};
			lc.addEventListener(StatusEvent.STATUS, 
				function (event:StatusEvent):void{
					if(lastStatus != event.level && event.level == "error" && 
								event.target.client.hasOwnProperty('request')){
						var channel:int = event.target.client.$channel;
						var request:Object = event.target.client.request;
						if(request.channel != EXTERNAL_LOG_CHANNEL)				
							trace("Warning Undeliverable Messages: " + channel + " -> " + request.channel + "\n" + request.params);
					}
					lastStatus = event.level;
				}
			);
			//Workaround against Adobe bug: https://bugs.adobe.com/jira/browse/SDK-13565
			lc.client.$send = function(params:*, channel:int):void{
				var msg:String = (params is Array ? params.join(ARRAY_DELIMITER) : String(params));
				lc.client.request = {channel:channel, params:params}
				lc.send(loggerConnectionName + channel, "$progress", "INIT_STATUS");
				while(msg && msg.length){
					lc.send(loggerConnectionName + channel, "$progress", "SENDING_STATUS", msg.substring(0, Logger.CHAR_LIMIT));
					msg = msg.substring(Logger.CHAR_LIMIT);
				}
				lc.send(loggerConnectionName + channel, "$progress", "COMPLETE_STATUS");
			};
			lc.client.$progress = function(status:String, substring:String=null):void {
				if(status == "INIT_STATUS"){
					message = "";
				}else if(status == "COMPLETE_STATUS"){
					var parameters:Array = message.split(ARRAY_DELIMITER);
					lc.client.$result.apply(null, parameters);
				}else if(status == "SENDING_STATUS"){
					message += substring;
				}
			};
			lc.client.$terminate = function(channel:int):void{
				try{
					lc.close();
					if(lc.client.$status is Function)
						lc.client.$status(channel, "terminate", "Connection terminated: Connection name is already being used by another SWF");
				}catch(error:Error){trace(error)}
			};
		
			if(resultHandler != null){ 
				try{
					clearInterval(_connectionInterval);
					lc.connect(loggerConnectionName + channel);
					if(lc.client.$status is Function)
						lc.client.$status(channel, "ready", "Connection opened.");
					_localConnectionClient = lc.client;
				} catch (error:ArgumentError) {
					lc.send(loggerConnectionName + channel, "$terminate", channel);
					_connectionInterval = setInterval(_connect, 500, channel, resultHandler, statusHandler);
				}
			}
			return lc;
		}
		
		//Utils
		private static var refCount:int = 0;
		
		private static function formatDate(date:Date):String{
			return date.hours + '-' + date.minutes + '-' + date.seconds;
		}
		
		private static function toString(value:Object):String{
			refCount = 0;
			return internalToString(value);
		}
		
		private static function internalToString(value:Object, 
                                             indent:int = 0,
                                             refs:Object = null, 
                                             namespaceURIs:Array = null, 
                                             exclude:Array = null):String{
                                             
			var type:String = (value == null) ? "null" : typeof(value);
			if(type == "xml"){
				return value.toXMLString();
			}else if(type == "object"){
				if (value is Date)
                    return value.toString();
                else if (value is XMLNode)
                    return value.toString();
                else if (value is Class)
                    return "(" + getQualifiedClassName(value) + ")";
                else{
                	var str:String;
                    var classInfo:Object = getClassInfo(value, exclude,
                        { includeReadOnly: true, uris: namespaceURIs });
                        
                    var properties:Array = classInfo.properties;
                    
                    str = "(" + classInfo.name + ")";
                    
                    if (refs == null)
                        refs = new Object();

                    // Check to be sure we haven't processed this object before
                    var id:Object = refs[value];
                    if (id != null){
                        str += "#" + int(id);
                        return str;
                    }
                    
                    if (value != null){
                        str += "#" + refCount.toString();
                        refs[value] = refCount;
                        refCount++;
                    }

                    var isArray:Boolean = value is Array;
                    var isDict:Boolean = (classInfo.name == "flash.utils::Dictionary");
                    var prop:*;
                    indent += 2;
                    
                    // Print all of the variable values.
                    var array:Array = [str];
                    for (var j:int = 0; j < properties.length; j++){
                    	str = "";
                        prop = properties[j];
                        
                        if (isArray)
                            str += "[";
                        else if (isDict)
                            str += "{";

                    
                        if (isDict){
                            // in dictionaries, recurse on the key, because it can be a complex object
                            str += internalToString(prop, indent, refs,
                                                    namespaceURIs, exclude);
                        }else{
                            str += prop.toString();
                        }
                        
                        if (isArray)
                            str += "] ";
                        else if (isDict)
                            str += "} = ";
                        else
                            str += " = ";
                        
                        try{
                            // print the value
                            str += internalToString(value[prop], indent, refs,
                                                    namespaceURIs, exclude);
                        }catch(e:Error){
                            str += "?";
                        }
                        array.push(str);
                    }
                    indent -= 2;
                    return array.join('\n');
                }
				return value;
			}else{
				return String(value);
			}
		}
		
		private static function getClassInfo(obj:Object,
                                        excludes:Array = null,
                                        options:Object = null):Object
	    {   
	        var n:int;
	        var i:int;
	
	        if (options == null)
	            options = { includeReadOnly: true, uris: null, includeTransient: true };
	
	        var result:Object;
	        var propertyNames:Array = [];
	        var cacheKey:String;
	
	        var className:String;
	        var classAlias:String;
	        var properties:XMLList;
	        var prop:XML;
	        var dynamic:Boolean = false;
	        var metadataInfo:Object;
	
	        if (typeof(obj) == "xml"){
	            className = "XML";
	            properties = obj.text();
	            if (properties.length())
	                propertyNames.push("*");
	            properties = obj.attributes();
	        }else{
	            var classInfo:XML = describeType(obj);
	            className = classInfo.@name.toString();
	            classAlias = classInfo.@alias.toString();
	            dynamic = (classInfo.@isDynamic.toString() == "true");
	
	            if (options.includeReadOnly)
	                properties = classInfo..accessor.(@access != "writeonly") + classInfo..variable;
	            else
	                properties = classInfo..accessor.(@access == "readwrite") + classInfo..variable;
	
	            var numericIndex:Boolean = false;
	        }
		
	        result = {};
	        result["name"] = className;
	        result["alias"] = classAlias;
	        result["properties"] = propertyNames;
	        result["dynamic"] = dynamic;
	        	        
	        var excludeObject:Object = {};
	        if (excludes){
	            n = excludes.length;
	            for (i = 0; i < n; i++)
	                excludeObject[excludes[i]] = 1;
	        }
	
	        //TODO this seems slightly fragile, why not use the 'is' operator?
	        var isArray:Boolean = (className == "Array");
	        var isDict:Boolean  = (className == "flash.utils::Dictionary");
	        
	        if (isDict){
	            // dictionaries can have multiple keys of the same type,
	            // (they can index by reference rather than QName, String, or number),
	            // which cannot be looked up by QName, so use references to the actual key
	            for (var key:* in obj)
	                propertyNames.push(key);
	        }else if (dynamic){
	            for (var p:String in obj)
	            {
	                if (excludeObject[p] != 1)
	                {
	                    if (isArray)
	                    {
	                         var pi:Number = parseInt(p);
	                         if (isNaN(pi))
	                            propertyNames.push(new QName("", p));
	                         else
	                            propertyNames.push(pi);
	                    }
	                    else
	                    {
	                        propertyNames.push(new QName("", p));
	                    }
	                }
	            }
	            numericIndex = isArray && !isNaN(Number(p));
	        }
	
	        if (isArray || isDict || className == "Object"){
	            // Do nothing since we've already got the dynamic members
	        }else if (className == "XML"){
	            n = properties.length();
	            for (i = 0; i < n; i++){
	                p = properties[i].name();
	                if (excludeObject[p] != 1)
	                    propertyNames.push(new QName("", "@" + p));
	            }
	        }else{
	            n = properties.length();
	            var uris:Array = options.uris;
	            var uri:String;
	            var qName:QName;
	            for (i = 0; i < n; i++)
	            {
	                prop = properties[i];
	                p = prop.@name.toString();
	                uri = prop.@uri.toString();
	                
	                if (excludeObject[p] == 1)
	                    continue;
	                    
	                if (!options.includeTransient)
	                    continue;
	                
	                if (uris != null){
	                    if (uris.length == 1 && uris[0] == "*"){   
	                        qName = new QName(uri, p);
	                        try{
	                            obj[qName]; // access the property to ensure it is supported
	                            propertyNames.push();
	                        }catch(e:Error){
	                            // don't keep property name 
	                        }
	                    }else{
	                        for (var j:int = 0; j < uris.length; j++){
	                            uri = uris[j];
	                            if (prop.@uri.toString() == uri){
	                                qName = new QName(uri, p);
	                                try{
	                                    obj[qName];
	                                    propertyNames.push(qName);
	                                }catch(e:Error){
	                                    // don't keep property name 
	                                }
	                            }
	                        }
	                    }
	                }
	                else if (uri.length == 0)
	                {
	                    qName = new QName(uri, p);
	                    try{
	                        obj[qName];
	                        propertyNames.push(qName);
	                    }catch(e:Error){
	                        // don't keep property name 
	                    }
	                }
	            }
	        }
	
	        propertyNames.sort(Array.CASEINSENSITIVE |
	                           (numericIndex ? Array.NUMERIC : 0));
	
	        // dictionary keys can be indexed by an object reference
	        // there's a possibility that two keys will have the same toString()
	        // so we don't want to remove dupes
	        if (!isDict){
	            // for Arrays, etc., on the other hand...
	            // remove any duplicates, i.e. any items that can't be distingushed by toString()
	            for (i = 0; i < propertyNames.length - 1; i++){
	                // the list is sorted so any duplicates should be adjacent
	                // two properties are only equal if both the uri and local name are identical
	                if (propertyNames[i].toString() == propertyNames[i + 1].toString()){
	                    propertyNames.splice(i, 1);
	                    i--; // back up
	                }
	            }
	        }
	        return result;
	    }
	}
}