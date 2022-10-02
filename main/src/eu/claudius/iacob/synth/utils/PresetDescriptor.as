package eu.claudius.iacob.synth.utils {
public class PresetDescriptor {

    private var _number:uint;
    private var _label:String;

    public function PresetDescriptor(number:uint, label:String) {
        _number = number;
        _label = label;
    }

    public function get number():uint {
        return _number;
    }

    public function get label():String {
        return _label;
    }

    public function toString () : String {
        return "PresetDescriptor {" + _number + ', ' + _label + '}';
    }
}
}
