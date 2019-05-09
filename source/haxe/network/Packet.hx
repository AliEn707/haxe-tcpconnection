package haxe.network;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import lime.utils.CompressionAlgorithm;


class Chank{
	public var type:Int;
	public var data:Dynamic=null;
	
	public function new(id){
		type=id;
	}
	
	public function isByte():Bool{
		return type == 1;
	}
	
	public function isShort():Bool{
		return type == 2;
	}
	
	public function isInt():Bool{
		return type == 3;
	}
	
	public function isFloat():Bool{
		return type == 4;
	}
	
	public function isDouble():Bool{
		return type == 5;
	}
	
	public function isString():Bool{
		return type == 6;
	}
	
	public function isBytes():Bool{
		return type == 7;
	}
	
	public function isCompressed():Bool{
		return type == 8;
	}
	
	public function getInt():Int{
		return data;
	}
	
	public function getFloat():Float{
		return data;
	}
	
	public function getString():String{
		return data;
	}
	
	public function getBytes():Bytes{
		return data;
	}
}

class Packet{
	
	public var chanks:Array<Chank>;
	public var type:Int;
	
	public function new(){
		init();
	}
	
	public function init():Void{
		chanks = [];
	}
	
	public function addByte(a:Int):Void{
		var c:Chank=new Chank(1);
		c.data=a;
		chanks.push(c);
	}
	
	public function addShort(a:Int):Void{
		var c:Chank=new Chank(2);
		c.data=a;
		chanks.push(c);
	}
	
	public function addInt(a:Int):Void{
		var c:Chank=new Chank(3);
		c.data=a;
		chanks.push(c);
	}
	
	public function addFloat(a:Float):Void{
		var c:Chank=new Chank(4);
		c.data=a;
		chanks.push(c);
	}
	
	public function addDouble(a:Float):Void{
		var c:Chank=new Chank(5);
		c.data=a;
		chanks.push(c);
	}
	
	public function addString(a:String):Void{
		var c:Chank=new Chank(6);
		c.data=a;
		chanks.push(c);
	}
	
	public function addBytes(a:Bytes):Void{
		var c:Chank=new Chank(7);
		c.data=a;
		chanks.push(c);
	}
	
	public function addCompressed(a:Bytes):Void{
		var c:Chank=new Chank(8);
		c.data=a;
		chanks.push(c);
	}
	
	public function getBytes():Bytes{
		var buf:BytesOutput = new BytesOutput();
		var size = 2;
		buf.bigEndian = false;
		buf.writeUInt16(0);
		buf.writeInt8(type);
		buf.writeInt8(chanks.length>125 ? -1 : chanks.length);
		for (c in chanks){
			if (c.type>0 && c.type<7){
				buf.writeInt8(c.type);
				switch c.type {
					case 1: 
						buf.writeInt8(c.data);
						size+= 1;
					case 2: 
						buf.writeInt16(c.data);
						size+= 2;
					case 3: 
						buf.writeInt32(c.data);
						size+= 4;
					case 4: 
						buf.writeFloat(c.data);
						size+= 4;
					case 5: 
						buf.writeDouble(c.data);
						size+= 8;
					case 6: 
						var ss = cast(c.data, String).length;
						buf.writeUInt16(ss);
						buf.writeString(c.data);
						size+= ss;
					case 7: 
						var ss = cast(c.data, Bytes).length;
						buf.writeUInt16(ss);
						buf.write(c.data);
						size+= ss;
					case 8: 
						var data:Bytes = cast(c.data, lime.utils.Bytes).compress(CompressionAlgorithm.LZMA);
						var ss = data.length;
						buf.writeUInt16(ss);
						buf.write(data);
						size+= ss;
					default: trace("wrong chank");
				}
			}
		}
		var bytes:Bytes = buf.getBytes();
		bytes.setUInt16(0, size);
		return bytes;
	}
	
	public static function fromBytes(b:Bytes):Packet{
		var p:Packet = new Packet();
		var bi:BytesInput = new BytesInput(b);
		var size = b.length;
		p.type = bi.readInt8();
		size--;
		bi.readInt8();//number of chanks
		size--;
		while(size>1){
			var type:Int = bi.readInt8();
			size--;
			var c:Chank = new Chank(type);
			switch type {
				case 1: 
					c.data = bi.readInt8();
					size-= 1;
				case 2: 
					c.data=bi.readInt16();
					size-= 2;
				case 3: 
					c.data=bi.readInt32();
					size-= 4;
				case 4: 
					c.data=bi.readFloat();
					size-= 4;
				case 5: 
					c.data=bi.readDouble();
					size-= 8;
				case 6: 
					var s:Int = bi.readUInt16();
					c.data=bi.readString(s);
					size-= s+2;
				case 7: 
					var s:Int = bi.readUInt16();
					c.data=bi.read(s);
					size-= s+2;
				case 8: 
					var s:Int = bi.readUInt16();
					c.data=cast(bi.read(s), lime.utils.Bytes).compress(CompressionAlgorithm.LZMA);
					size-= cast(c.data,Bytes).length+2;
			}
			p.chanks.push(c);
		}
		return p; 
	}
}