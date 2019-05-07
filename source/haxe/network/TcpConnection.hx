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
				var p:Packet = new Packet();
				p.size = size;
				p.type = _sock.readByte();
				size--;
				_sock.readByte();//number of chanks
				size--;
				while(size>1){
					var type:Int = _sock.input.readInt8();
					size--;
					var c:Chank = new Chank(type);
					switch type {
						case 1: 
							c.i = _sock.readByte();
							size-= 1;
						case 2: 
							c.i=_sock.readShort();
							size-= 2;
						case 3: 
							c.i=_sock.readInt();
							size-= 4;
						case 4: 
							c.f=_sock.readFloat();
							size-= 4;
						case 5: 
							c.f=_sock.readDouble();
							size-= 8;
						case 6: 
							c.s=_sock.input.readUTF();
							size-= c.s.length+2;
					}
					p.chanks.push(c);
				}
				delay(callback.bind(p));
			}));
			_workflow.unshift(function():Bool{return true;});
		}));
	#else
		_worker.sendMessage(function(){
			var p:Packet = new Packet();
			p.size = _sock.input.readUInt16();
			var size = p.size;
			p.type = _sock.input.readInt8();
			size--;
			_sock.input.readInt8();//number of chanks
			size--;
			while(size>1){
				var type:Int = _sock.input.readInt8();
				size--;
				var c:Chank = new Chank(type);
				switch type {
					case 1: 
						c.i = _sock.input.readInt8();
						size-= 1;
					case 2: 
						c.i=_sock.input.readInt16();
						size-= 2;
					case 3: 
						c.i=_sock.input.readInt32();
						size-= 4;
					case 4: 
						c.f=_sock.input.readFloat();
						size-= 4;
					case 5: 
						c.f=_sock.input.readDouble();
						size-= 8;
					case 6: 
						var s:Int = _sock.input.readUInt16();
						c.s=_sock.input.readString(s);
						size-= c.s.length+2;
				}
				p.chanks.push(c);
			}
			_main.sendMessage(callback.bind(p)); 
		});
	#end
	}

	public function sendPacket(p:Packet):Void{
		var buf:BytesOutput = new BytesOutput();
		buf.bigEndian = false;
		buf.writeInt16(p.size+2);
		buf.writeInt8(p.type);
		buf.writeInt8(p.chanks.length>125 ? -1 : p.chanks.length);
		for (c in p.chanks){
			if (c.type>0 && c.type<7){
				buf.writeInt8(c.type);
				switch c.type {
					case 1: 
						buf.writeInt8(c.i);
					case 2: 
						buf.writeInt16(c.i);
					case 3: 
						buf.writeInt32(c.i);
					case 4: 
						buf.writeFloat(c.f);
					case 5: 
						buf.writeDouble(c.f);
					case 6: 
						buf.writeInt16(c.s.length);
						buf.writeString(c.s);
//					default: trace("wrong chank");
				}
			}
		}
		write.lock();
			sendBytes(buf.getBytes());
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
	public function listen(port:Int, callback:TcpConnection->Void, ?fail:Dynamic->Void, host:String = "0.0.0.0", maxconnections:Int = 0){
        _timer.run = _checkWorkflow;
		_worker=Thread.create(function(){
			_sock.bind(new sys.net.Host(host), port);
			_sock.listen(maxconnections);
//	        trace("Starting server...");
			try{
				while( true ) {
					var c:Socket = _sock.accept();
					_main.sendMessage(function(){
						var conn:TcpConnection = new TcpConnection();
						conn._sock = c;
						conn._sock.input.bigEndian = false;
						conn._sock.output.bigEndian = false;
						conn._sock.setFastSend(true);
						conn._timer.run = conn._checkWorkflow;
						conn._worker = Thread.create(_doWork);
						callback(conn);
					});
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