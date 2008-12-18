var id = "ASLogger";
var flashParams = {
	src:"http://online-as-logger.googlecode.com/svn/trunk/demo/Logger.swf",
	wmode:"transparent",
	allowScriptAccess:"always"
};
if (document.all){
	var str = '<object id="' + id + '" classid="clsid:d27cdb6e-ae6d-11cf-96b8-444553540000">';
	for (var i in flashParams)
		str += '<param name="' + i + '" value="' + flashParams[i] + '"/>';
	str += '</object>';
} else {
	var str = '<embed id="' + id + '" name="' + id + '" type="application/x-shockwave-flash" pluginspage="http://www.adobe.com/go/getflashplayer" ';
	for (var i in flashParams)
		str += i + '="' + flashParams[i] + '" ';
	str += '> </embed>';
}
document.write('<div style="position:absolute;width:1px;height:1px">' + str + '</div>');

var Logger = new function(){
	this.trace = function(o, status){
		try{
			var logger = (document.all ? window["ASLogger"] : document["ASLogger"]);
			if(logger)
				logger.js_trace(status ? status : "log", o);
		}catch(e){}
	};
	this.debug = function(o){ Logger.trace(o, "log")  };
	this.info  = function(o){ Logger.trace(o, "info") };
	this.warn  = function(o){ Logger.trace(o, "warn") };
	this.error = function(o){ Logger.trace(o, "error")};
};