package haxe.network;

import haxe.network.Packet.Chank;
import haxe.CallStack;
import haxe.Timer;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesOutput;
#if flash
import flash.net.Socket;
import flash.errors.*;
#else
import sys.net.Socket;
import sys.net.Host;
#end
import haxe.crypto.Md5;
import haxe.crypto.Base64;
import haxe.Timer.delay;

#if cpp
import cpp.vm.Thread;
#elseif neko
import neko.vm.Thread;
#elseif java
import java.vm.Thread;
#elseif flash
#end

class TcpConnection{
	public var write:Lock = new Lock();
	public var read:Lock = new Lock();
	public var sock:Null<Socket> = null;
	
	private var _timer:Timer = new Timer(100); //TODO: check delay value
	private var _fail:Null<Dynamic->Void>;
	
#if flash
	private var _workflow:Array<Void->Void> = new Array<Void->Void>();
#else
	private var _worker:Thread;
	private var _main:Thread;
#end

	public function new(){
		sock = new Socket();
	#if !flash
		_main = Thread.current();
	#end
	}
	
#if flash	
	private function _connect(host:String, port:Int, ?success:TcpConnection->Void, ?fail:Dynamic->Void){
		try{
			sock.connect(host, port);
			sock.endian = LITTLE_ENDIAN;
			_timer.run = _checkWorkflow;
			if (success != null)
				success(this);
		}catch (e:Dynamic){
			_timer.stop();
			if (fail != null)
				fail(e);
		}
	}
#else	
	private function _connect(){
		var host:String = Thread.readMessage(true);
		var port:Int = Thread.readMessage(true);
		var success:Null<TcpConnection->Void> = Thread.readMessage(true);
		var fail:Null<Dynamic->Void> = Thread.readMessage(true);
		try{
			sock.connect(new Host(host), port);
			sock.input.bigEndian = false;
			sock.output.bigEndian = false;
			sock.setFastSend(true);
			if (success != null)
				success(this);
			_doWork();
		}catch (e:Dynamic){
			_timer.stop();
			if (fail != null)
				fail(e);
		}
	}
	
	private function _doWork(){
		try{
			while (true){
				cast(Thread.readMessage(true))();
			}
		}catch (e:Dynamic){
			if (_fail != null)
				_fail(e);
		}
	}
#end

	public function connect(host:String, port:Int, ?success:TcpConnection->Void, ?fail:Dynamic->Void){
		_fail = fail;
		#if flash
			delay(_connect.bind(host, port, success, fail), 33);
		#else
			_worker = Thread.create(_connect);
			_worker.sendMessage(host);
			_worker.sendMessage(port);
			_worker.sendMessage(success);
			_worker.sendMessage(fail);
			_timer.run = _checkWorkflow;
		#end
	}
	
	public function close(){
		sock.close();
	}

	public function setFailCallback(fail:Dynamic->Void){
		_fail = fail;
	}
	
#if flash 
	private function bytesAvailable(size:UInt):Bool{
//		trace(sock.bytesAvailable);
		return sock.bytesAvailable>=size;
	}
#end

	public function recvByte(callback:Int->Void){
	#if flash
		_workflow.push(_workerAction.bind(1, function(){
			delay(callback.bind(sock.readByte()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(sock.input.readInt8())); 
		});
	#end
	}

	public function recvShort(callback:Int->Void){
	#if flash
		_workflow.push(_workerAction.bind(2, function(){
			delay(callback.bind(sock.readShort()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(sock.input.readInt16())); 
		});
	#end
	}

	public function recvUShort(callback:UInt->Void){
	#if flash
		_workflow.push(_workerAction.bind(2, function(){
			delay(callback.bind(sock.readUnsignedShort()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(sock.input.readUInt16())); 
		});
	#end
	}

	public function recvInt(callback:Int->Void){
	#if flash
		_workflow.push(_workerAction.bind(4, function(){
			delay(callback.bind(sock.readInt()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(sock.input.readInt32())); 
		});
	#end
	}

	public function recvFloat(callback:Float->Void){
	#if flash
		_workflow.push(_workerAction.bind(4, function(){
			delay(callback.bind(sock.readFloat()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(sock.input.readFloat())); 
		});
	#end
	}

	public function recvDouble(callback:Float->Void){
	#if flash
		_workflow.push(_workerAction.bind(8, function(){
			delay(callback.bind(sock.readDouble()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(sock.input.readDouble())); 
		});
	#end
	}

	public function recvBytes(callback:Bytes->Void, ?size:Null<Int>){
	#if flash
		if (size == null){
			_workflow.push(_workerAction.bind(2, function(){
				delay(callback.bind(Bytes.ofString(sock.readUTF())),1);
			}));
		}else{
			_workflow.push(_workerAction.bind(size, function(){
				delay(callback.bind(Bytes.ofString(sock.readUTFBytes(size))),1);
			}));
		}
	#else
		_worker.sendMessage(function(){
			if (size==null)
				size=sock.input.readUInt16();
			_main.sendMessage(callback.bind(sock.input.read(size))); 
		});
	#end
	}

	public function recvString(callback:String->Void, ?size:Null<Int>){
	#if flash
		if (size == null){
			_workflow.push(_workerAction.bind(2, function(){
				delay(callback.bind(sock.readUTF()), 1);
			}));
		}else{
			_workflow.push(_workerAction.bind(size, function(){
				delay(callback.bind(sock.readUTFBytes(size)), 1);
			}));
		}
	#else
		_worker.sendMessage(function(){
			if (size==null)
				size=sock.input.readUInt16();
			_main.sendMessage(callback.bind(sock.input.readString(size))); 
		});
	#end
	}

	public function sendByte(a:Int):Void{
	#if flash
		sock.writeByte(a);
		sock.flush();
	#else
		sock.output.writeInt8(a);
	#end
	}

	public function sendShort(a:Int):Void{
	#if flash
		sock.writeShort(a);
		sock.flush();
	#else
//		_worker.sendMessage(function(){
		sock.output.writeInt16(a);
//		});
	#end
	}

	public function sendUShort(a:UInt):Void{
	#if flash
		sock.writeShort(a); //TODO:check
		sock.flush();
	#else
//		_worker.sendMessage(function(){
		sock.output.writeUInt16(a);
//		});
	#end
	}

	public function sendInt(a:Int):Void{
	#if flash
		sock.writeInt(a);
		sock.flush();
	#else
//		_worker.sendMessage(function(){
		sock.output.writeInt32(a);
//		});
	#end
	}

	public function sendFloat(a:Float):Void{
	#if flash
		sock.writeFloat(a);
		sock.flush();
	#else
//		_worker.sendMessage(function(){
		sock.output.writeFloat(a);
//		});
	#end
	}

	public function sendDouble(a:Float):Void{
	#if flash
		sock.writeDouble(a);
		sock.flush();
	#else
//		_worker.sendMessage(function(){
		sock.output.writeDouble(a);	
//		});
	#end
	}

	public function sendBytes(s:Bytes):Void{
	#if flash
		sock.writeBytes(s.getData(), 0, s.length);
		sock.flush();
	#else
//		_worker.sendMessage(function(){
			sock.output.write(s);	
//		});
	#end
	}

	public function sendString(s:String):Void{
	#if flash
		sock.writeUTF(s);//unsigned!!
		sock.flush();
	#else
//		_worker.sendMessage(function(){
			sock.output.writeUInt16(s.length);
			sock.output.writeString(s); 
//		});
	#end
	}
	
	public function recvPacket(callback:Packet->Void){
	#if flash
		_workflow.push(_workerAction.bind(2, function(){
			var size:UInt = sock.readUnsignedShort();
			_workflow.shift();
			_workflow.unshift(_workerAction.bind(size, function(){
				delay(callback.bind(Packet.fromBytes(Bytes.ofString(sock.readUTFBytes(size)))), 1);
			}));
			_workflow.unshift(function():Bool{return true;});
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(Packet.fromBytes(sock.input.read(sock.input.readUInt16())))); 
		});
	#end
	}

	public function sendPacket(p:Packet):Void{
		var bytes:Bytes = p.getBytes();
		write.lock();
			sendUShort(bytes.length);
			sendBytes(bytes);
		write.unlock();		
	}
	
	private function _checkWorkflow(){
	#if flash
		try{
			while(_workflow.length > 0){
				var work = _workflow[0];
				work();
				_workflow.shift();
				work = null;
			}
		}catch(e:Dynamic){
			//trace(e);
		}
	#else
		try{
			var work:Null<Void->Void>;
			do{
				work = Thread.readMessage(false);
				if (work != null)
					work();
			}while(work != null);
		}catch(e:Dynamic){
			trace(e);
		}
	#end
	}
/*	
	private function repeater(callback:Void->Bool){
		if (!callback())
			delay(repeater.bind(callback), 10);
	}
*/	
#if flash
	private function _workerAction(size:Int, callback:Void->Void):Bool{
		if (bytesAvailable(size)){
			try{
				callback();	
				return true;
			}catch(eof:EOFError){
			}catch(e:Dynamic){
				_timer.stop();
				if (_fail != null)
					_fail(e);
			}
		}
		return false;
	}
#end
#if !flash
	static inline var policy:String = "< cross - domain - policy >< allow - access - from domain =\" *\" to - ports =\" *\" /></cross - domain - policy > ";
	
	public function listen(port:Int, connected:TcpConnection->Void, ?created:TcpConnection->Void, ?fail:Dynamic->Void, host:String = "0.0.0.0", maxconnections:Int = 0){
        _timer.run = _checkWorkflow;
		_worker=Thread.create(function(){
			try{
				sock.bind(new sys.net.Host(host), port);
				sock.listen(maxconnections);
//	        	trace("Starting server...");
				if (created != null)
				created(this);

				while( true ) {
					var c:Socket = sock.accept();
					c.setTimeout(2);
					var p = c.input.read(2);
					if (p.toString() == "<p"){//flash policy ask
						c.setFastSend(true);
						c.output.write(Bytes.ofString(policy));
						c.close();
					}else{
						_main.sendMessage(function(){
							var conn:TcpConnection = new TcpConnection();
							conn.sock = c;
							conn.sock.setTimeout(0);
							conn.sock.input.bigEndian = false;
							conn.sock.output.bigEndian = false;
							conn.sock.setFastSend(true);
							conn._timer.run = conn._checkWorkflow;
							conn._worker = Thread.create(_doWork);
							connected(conn);
						});
					}
				}
			}catch (e:Dynamic){
				trace(e);
				if (fail != null)
					fail(e);
			}
			_timer.stop();
			sock.close();
		});
	}


	/**
	 * Get local ip address, required internet for correct work, otherwise may return 127.0.0.1;
	 * @return
	 */
	public static function getMyHost():String{
		try{
			var s = new sys.net.Socket();
			s.connect(new sys.net.Host("ya.ru"), 80);
			var host = s.host().host.toString();
			s.close();
			return host;
		}catch (e:Dynamic){trace(e); };
		return new sys.net.Host(sys.net.Host.localhost()).toString();
	}

	public static function isAvailable(host:String, port:Int):Bool{
		var s = new sys.net.Socket();
		try{
			s.setTimeout(0.1);
			s.connect(new sys.net.Host(host), port);
			s.setTimeout(0.1);
			s.output.writeByte(1);
			s.close();
			return true;
		}catch(e:Dynamic){
			trace(e);
		}
		return false;
	}
	
#end
}