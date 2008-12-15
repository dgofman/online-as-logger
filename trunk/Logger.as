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
	import flash.utils.getTimer;
	import flash.utils.setTimeout;
	
	import mx.controls.Alert;
	import mx.formatters.DateFormatter;
	import mx.utils.ObjectUtil;
	
	public class Logger extends Sprite
	{
		private var _level:int;
		private var _type:String;
	
		private static var _xpanel_lc:LocalConnection;
		private static var _loggerEventManager:Object;
		
		private static const _dateFormatter:DateFormatter = new DateFormatter();

		private static const xpanelConnectionName:String = "_xpanel1";
		private static const loggerConnectionName:String = "_logger1";
		private static const bridgeConnectionName:String = "_logger2";
		
		public static const LOGGER_DEBUG:Logger       = new Logger(0x01, 'log');
		public static const LOGGER_INFORMATION:Logger = new Logger(0x02, 'info');
		public static const LOGGER_WARNING:Logger     = new Logger(0x04, 'warn');
		public static const LOGGER_ERROR:Logger       = new Logger(0x08, 'error');
				
		public static const CHAR_LIMIT:uint = 40950; //LocalConnection error: 2084 The AMF encoding of the arguments cannot exceed 40K. 
		
		private static var _js_bridge_initialized:Boolean = false;
		
		public function Logger(level:int=-1, type:String=null){
			if(_js_bridge_initialized == false && ExternalInterface.available){
				ExternalInterface.addCallback("js_trace", js_trace);
				_js_bridge_initialized = true;
			}
			this._level = level;
			this._type = type;

			_dateFormatter.formatString = 'H:NN:SS A';
		}
		
		public function get level():int{
			return _level;
		}
		
		public function get type():String{
			return _type;
		}

		public static function alert(o:Object):Alert{
			return Alert.show(String(o));
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
			_send(LOGGER_DEBUG, (args is Array ? args.join(', ') : args));
		}
		
		private function js_trace(type:String="log", o:Object=null):void{
			var loggers:Array = [LOGGER_DEBUG, LOGGER_INFORMATION, LOGGER_WARNING, LOGGER_ERROR];
			for(var i:uint = 0; i < loggers.length; i++){
				if(loggers[i].type == type){
					_send(loggers[i] as Logger, o);
					return;
				}
			}
			ExternalInterface.call('console.' + type, _dateFormatter.format(new Date()) + '  ' + o);
		}

		private static function _send(logger:Logger, o:Object):void{
			try{
				var str:String = (typeof o == 'xml' ? o.toXMLString() : ObjectUtil.toString(o));
				//Send message to FireBug console
				ExternalInterface.call('console.' + logger.type, _dateFormatter.format(new Date()) + '  ' + str);
				//Send message to Flex Logger
				if(_loggerEventManager == null)
					connect();
				_loggerEventManager.$send(getTimer(), str, logger.level);
				//Send message to XPanel
				if(_xpanel_lc == null)
					_xpanel_lc = new LocalConnection();
				if(str && str.length > CHAR_LIMIT)
					str = str.substring(0, CHAR_LIMIT); 
				_xpanel_lc.addEventListener(StatusEvent.STATUS, function (event:StatusEvent):void{});
				_xpanel_lc.send(xpanelConnectionName, "dispatchMessage", getTimer(), str, logger.level);
			}
			catch (err:Error){
				// ignored.
			}
		}
		
		//Workaround against Adobe bug: https://bugs.adobe.com/jira/browse/SDK-13565
		public static function connect(resultHandler:Function=null, statusHandler:Function=null):void{
			var message:String;
			var ARRAY_DELIMITER:String = "\u00B6";
			var lc:LocalConnection = new LocalConnection();
			var lastStatus:String;
			lc.client = _loggerEventManager = {$result:resultHandler, $status:statusHandler};
			lc.addEventListener(StatusEvent.STATUS, 
				function (event:StatusEvent):void{
					if(lastStatus != event.level && event.level == "error")
						trace("Error: Connection corrupted or disconnected");
					lastStatus = event.level;
				}
			);
			_loggerEventManager.$send = function(...parameters):void{
				lc.send(loggerConnectionName, "$progress", "INIT_STATUS");
				if(parameters != null){
					var msg:String = (parameters is Array ? parameters.join(ARRAY_DELIMITER) : String(parameters));
					while(msg.length){
						lc.send(loggerConnectionName, "$progress", "SENDING_STATUS", msg.substring(0, Logger.CHAR_LIMIT));
						msg = msg.substring(Logger.CHAR_LIMIT);
					}
				}
				lc.send(loggerConnectionName, "$progress", "COMPLETE_STATUS");
			};
			_loggerEventManager.$progress = function(status:String, substring:String=null):void {
				if(status == "INIT_STATUS"){
					message = "";
				}else if(status == "COMPLETE_STATUS"){
					var parameters:Array = message.split(ARRAY_DELIMITER);
					if(parameters is Array && parameters.length == 3)
						_loggerEventManager.$result.apply(null, parameters);
				}else if(status == "SENDING_STATUS"){
					message += substring;
				}
			};
			_loggerEventManager.$terminate = function():void{
				try{
					lc.close();
					if(_loggerEventManager.$status is Function)
						_loggerEventManager.$status("terminate", "Connection terminated: Connection name is already being used by another SWF");
				}catch(error:Error){trace(error)}
			};
		
			if(resultHandler != null){ 
				try{
					lc.connect(loggerConnectionName);
					if(_loggerEventManager.$status is Function)
						_loggerEventManager.$status("ready", "Connection opened.");
				} catch (error:ArgumentError) {
					lc.send(loggerConnectionName, "$terminate");
					setTimeout(connect, 500, resultHandler, statusHandler);
				}
			}
		}
	}
}