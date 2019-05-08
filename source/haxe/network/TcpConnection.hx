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
	
	private var _timer:Timer = new Timer(100); //TODO: check delay value
	private var _sock:Null<Socket> = null;
	private var _fail:Null<Dynamic->Void>;
	
#if flash
	private var _workflow:Array<Void->Void> = new Array<Void->Void>();
#else
	private var _worker:Thread;
	private var _main:Thread;
#end

	public function new(){
		_sock = new Socket();
	#if !flash
		_main = Thread.current();
	#end
	}
	
#if flash	
	private function _connect(host:String, port:Int, ?success:TcpConnection->Void, ?fail:Dynamic->Void){
		try{
			_sock.connect(host, port);
			_sock.endian = LITTLE_ENDIAN;
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
			_sock.connect(new Host(host), port);
			_sock.input.bigEndian = false;
			_sock.output.bigEndian = false;
			_sock.setFastSend(true);
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
		_sock.close();
	}

	public function setFailCallback(fail:Dynamic->Void){
		_fail = fail;
	}
	
#if flash 
	private function bytesAvailable(size:UInt):Bool{
//		trace(_sock.bytesAvailable);
		return _sock.bytesAvailable>=size;
	}
#end

	public function recvByte(callback:Int->Void){
	#if flash
		_workflow.push(_workerAction.bind(1, function(){
			delay(callback.bind(_sock.readByte()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(_sock.input.readInt8())); 
		});
	#end
	}

	public function recvShort(callback:Int->Void){
	#if flash
		_workflow.push(_workerAction.bind(2, function(){
			delay(callback.bind(_sock.readShort()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(_sock.input.readInt16())); 
		});
	#end
	}

	public function recvUShort(callback:UInt->Void){
	#if flash
		_workflow.push(_workerAction.bind(2, function(){
			delay(callback.bind(_sock.readUnsignedShort()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(_sock.input.readUInt16())); 
		});
	#end
	}

	public function recvInt(callback:Int->Void){
	#if flash
		_workflow.push(_workerAction.bind(4, function(){
			delay(callback.bind(_sock.readInt()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(_sock.input.readInt32())); 
		});
	#end
	}

	public function recvFloat(callback:Float->Void){
	#if flash
		_workflow.push(_workerAction.bind(4, function(){
			delay(callback.bind(_sock.readFloat()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(_sock.input.readFloat())); 
		});
	#end
	}

	public function recvDouble(callback:Float->Void){
	#if flash
		_workflow.push(_workerAction.bind(8, function(){
			delay(callback.bind(_sock.readDouble()), 1);
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(_sock.input.readDouble())); 
		});
	#end
	}

	public function recvBytes(callback:Bytes->Void, ?size:Null<Int>){
	#if flash
		if (size == null){
			_workflow.push(_workerAction.bind(2, function(){
				delay(callback.bind(Bytes.ofString(_sock.readUTF())));
			}));
		}else{
			_workflow.push(_workerAction.bind(size, function(){
				delay(callback.bind(Bytes.ofString(_sock.readUTFBytes(size))));
			}));
		}
	#else
		_worker.sendMessage(function(){
			if (size==null)
				size=_sock.input.readUInt16();
			_main.sendMessage(callback.bind(_sock.input.read(size))); 
		});
	#end
	}

	public function recvString(callback:String->Void, ?size:Null<Int>){
	#if flash
		if (size == null){
			_workflow.push(_workerAction.bind(2, function(){
				delay(callback.bind(_sock.readUTF()));
			}));
		}else{
			_workflow.push(_workerAction.bind(size, function(){
				delay(callback.bind(_sock.readUTFBytes(size)));
			}));
		}
	#else
		_worker.sendMessage(function(){
			if (size==null)
				size=_sock.input.readUInt16();
			_main.sendMessage(callback.bind(_sock.input.readString(size))); 
		});
	#end
	}

	public function sendByte(a:Int):Void{
	#if flash
		_sock.writeByte(a);
		_sock.flush();
	#else
		_sock.output.writeInt8(a);
	#end
	}

	public function sendShort(a:Int):Void{
	#if flash
		_sock.writeShort(a);
		_sock.flush();
	#else
		_worker.sendMessage(function(){_sock.output.writeInt16(a);});
	#end
	}

	public function sendUShort(a:UInt):Void{
	#if flash
		_sock.writeUnsignedShort(a);
		_sock.flush();
	#else
		_worker.sendMessage(function(){_sock.output.writeUInt16(a);});
	#end
	}

	public function sendInt(a:Int):Void{
	#if flash
		_sock.writeInt(a);
		_sock.flush();
	#else
		_worker.sendMessage(function(){_sock.output.writeInt32(a);});
	#end
	}

	public function sendFloat(a:Float):Void{
	#if flash
		_sock.writeFloat(a);
		_sock.flush();
	#else
		_worker.sendMessage(function(){_sock.output.writeFloat(a);});
	#end
	}

	public function sendDouble(a:Float):Void{
	#if flash
		_sock.writeDouble(a);
		_sock.flush();
	#else
		_worker.sendMessage(function(){_sock.output.writeDouble(a);});
	#end
	}

	public function sendBytes(s:Bytes):Void{
	#if flash
		_sock.writeBytes(s.getData(), 0, s.length);
		_sock.flush();
	#else
		_worker.sendMessage(function(){_sock.output.write(s);});
	#end
	}

	public function sendString(s:String):Void{
	#if flash
		_sock.writeUTF(s);//unsigned!!
		_sock.flush();
	#else
		_worker.sendMessage(function(){
			_sock.output.writeUInt16(s.length);
			_sock.output.writeString(s); 
		});
	#end
	}
	
	public function recvPacket(callback:Packet->Void){
	#if flash
		_workflow.push(_workerAction.bind(2, function(){
			var size:UInt = _sock.readUnsignedShort();
			_workflow.shift();
			_workflow.unshift(_workerAction.bind(size, function(){
				delay(callback.bind(Packet.fromBytes(Bytes.ofString(_sock.readUTFBytes(size)))));
			}));
			_workflow.unshift(function():Bool{return true;});
		}));
	#else
		_worker.sendMessage(function(){
			_main.sendMessage(callback.bind(Packet.fromBytes(_sock.input.read(_sock.input.readUInt16())))); 
		});
	#end
	}

	public function sendPacket(p:Packet):Void{
		write.lock();
			sendBytes(p.getBytes());
		write.unlock();		
	}
	
	private function _checkWorkflow(){
	#if flash
		while(_workflow.length > 0){
			var work = _workflow[0];
			if (work()){
				_workflow.shift();
				work = null;
			}else{
				break;
			}
		}
	#else
		try{
			var work:Void->Void = Thread.readMessage(false);
			if (work != null)
				work();
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
	
	public function listen(port:Int, callback:TcpConnection->Void, ?fail:Dynamic->Void, host:String = "0.0.0.0", maxconnections:Int = 0){
        _timer.run = _checkWorkflow;
		_worker=Thread.create(function(){
			_sock.bind(new sys.net.Host(host), port);
			_sock.listen(maxconnections);
//	        trace("Starting server...");
			try{
				while( true ) {
					var c:Socket = _sock.accept();
					c.setTimeout(2);
					var p = c.input.read(2);
					if (p.toString() == "<p"){//flash policy ask
						c.setFastSend(true);
						c.output.write(Bytes.ofString(policy));
						c.close();
					}else{
						_main.sendMessage(function(){
							var conn:TcpConnection = new TcpConnection();
							conn._sock = c;
							conn._sock.setTimeout(0);
							conn._sock.input.bigEndian = false;
							conn._sock.output.bigEndian = false;
							conn._sock.setFastSend(true);
							conn._timer.run = conn._checkWorkflow;
							conn._worker = Thread.create(_doWork);
							callback(conn);
						});
					}
				}
			}catch(e:Dynamic){
				if (fail != null)
					fail(e);
			}
			_sock.close();
		});
	}
#end
}