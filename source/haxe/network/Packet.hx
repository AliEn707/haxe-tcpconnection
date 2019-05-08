package haxe.network;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;


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
	
	public function getInt():Int{
		return data;
	}
	
	public function getFloat():Float{
		return data;
	}
	
	public function getString():String{
		return data;
	}
}

class Packet{
	
	public var chanks:Array<Chank>;
	public var type:Int;
	public var size:Int;
	
	public function new(){
		init();
	}
	
	public function init():Void{
		chanks = [];
		size = 0;
	}
	
	public function addByte(a:Int):Void{
		var c:Chank=new Chank(1);
		c.data=a;
		chanks.push(c);
		size+= 2;
	}
	
	public function addShort(a:Int):Void{
		var c:Chank=new Chank(2);
		c.data=a;
		chanks.push(c);
		size+= 3;
	}
	
	public function addInt(a:Int):Void{
		var c:Chank=new Chank(3);
		c.data=a;
		chanks.push(c);
		size+= 5;
	}
	
	public function addFloat(a:Float):Void{
		var c:Chank=new Chank(4);
		c.data=a;
		chanks.push(c);
		size+= 5;
	}
	
	public function addDouble(a:Float):Void{
		var c:Chank=new Chank(5);
		c.data=a;
		chanks.push(c);
		size+= 9;
	}
	
	public function addString(a:String):Void{
		var c:Chank=new Chank(6);
		c.data=a;
		chanks.push(c);
		size+= 1+2+a.length;
	}
	
	public function getBytes():Bytes{
		var buf:BytesOutput = new BytesOutput();
		buf.bigEndian = false;
		buf.writeUInt16(size+2);
		buf.writeInt8(type);
		buf.writeInt8(chanks.length>125 ? -1 : chanks.length);
		for (c in chanks){
			if (c.type>0 && c.type<7){
				buf.writeInt8(c.type);
				switch c.type {
					case 1: 
						buf.writeInt8(c.data);
					case 2: 
						buf.writeInt16(c.data);
					case 3: 
						buf.writeInt32(c.data);
					case 4: 
						buf.writeFloat(c.data);
					case 5: 
						buf.writeDouble(c.data);
					case 6: 
						buf.writeUInt16(cast(c.data, String).length);
						buf.writeString(c.data);
//					default: trace("wrong chank");
				}
			}
		}
		return buf.getBytes();
	}
	
	public static function fromBytes(b:Bytes):Packet{
		var p:Packet = new Packet();
		var bi:BytesInput = new BytesInput(b);
		var size = b.length;
		p.size = size;
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
					size-= cast(c.data,String).length+2;
			}
			p.chanks.push(c);
		}
		return p; 
	}
}