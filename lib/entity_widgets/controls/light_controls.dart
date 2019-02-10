part of '../../main.dart';

class LightControlsWidget extends StatefulWidget {

  @override
  _LightControlsWidgetState createState() => _LightControlsWidgetState();

}

class _LightControlsWidgetState extends State<LightControlsWidget> {

  int _tmpBrightness;
  int _tmpColorTemp = 0;
  HSVColor _tmpColor = HSVColor.fromAHSV(1.0, 30.0, 0.0, 1.0);
  bool _changedHere = false;
  String _tmpEffect;

  void _resetState(LightEntity entity) {
    _tmpBrightness = entity.brightness ?? 0;
    _tmpColorTemp = entity.colorTemp ?? entity.minMireds?.toInt();
    _tmpColor = entity.color ?? _tmpColor;
    _tmpEffect = entity.effect;
  }

  void _setBrightness(LightEntity entity, double value) {
    setState(() {
      _tmpBrightness = value.round();
      _changedHere = true;
      if (_tmpBrightness > 0) {
        eventBus.fire(new ServiceCallEvent(
            entity.domain, "turn_on", entity.entityId,
            {"brightness": _tmpBrightness}));
      } else {
        eventBus.fire(new ServiceCallEvent(
            entity.domain, "turn_off", entity.entityId,
            null));
      }
    });
  }

  void _setColorTemp(LightEntity entity, double value) {
    setState(() {
      _tmpColorTemp = value.round();
      _changedHere = true;
      eventBus.fire(new ServiceCallEvent(
          entity.domain, "turn_on", entity.entityId,
          {"color_temp": _tmpColorTemp}));
    });
  }

  void _setColor(LightEntity entity, HSVColor color) {
    setState(() {
      _tmpColor = color;
      _changedHere = true;
      Logger.d( "HS Color: [${color.hue}, ${color.saturation}]");
      eventBus.fire(new ServiceCallEvent(
        entity.domain, "turn_on", entity.entityId,
          {"hs_color": [color.hue, color.saturation*100]}));
    });
  }

  void _setEffect(LightEntity entity, String value) {
    setState(() {
      _tmpEffect = value;
      _changedHere = true;
      if (_tmpEffect != null) {
        eventBus.fire(new ServiceCallEvent(
            entity.domain, "turn_on", entity.entityId,
            {"effect": "$value"}));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entityModel = EntityModel.of(context);
    final LightEntity entity = entityModel.entityWrapper.entity;
    if (!_changedHere) {
      _resetState(entity);
    } else {
      _changedHere = false;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _buildBrightnessControl(entity),
        _buildColorTempControl(entity),
        _buildColorControl(entity),
        _buildEffectControl(entity)
      ],
    );
  }

  Widget _buildBrightnessControl(LightEntity entity) {
    if ((entity.supportBrightness) && (_tmpBrightness != null) && (entity.state != EntityState.unavailable)) {
      return UniversalSlider(
        onChanged: (value) {
          setState(() {
            _changedHere = true;
            _tmpBrightness = value.round();
          });
        },
        min: 0.0,
        max: 255.0,
        onChangeEnd: (value) => _setBrightness(entity, value),
        value: _tmpBrightness.toDouble(),
        leading: Icon(Icons.brightness_5),
        title: "Brightness",
      );
    } else {
      return Container(width: 0.0, height: 0.0);
    }
  }

  Widget _buildColorTempControl(LightEntity entity) {
    if (entity.supportColorTemp) {
      return UniversalSlider(
        title: "Color temperature",
        leading: Text("Cold", style: TextStyle(color: Colors.lightBlue),),
        value:  _tmpColorTemp.toDouble(),
        onChangeEnd: (value) => _setColorTemp(entity, value),
        max: entity.maxMireds,
        min: entity.minMireds,
        onChanged: (value) {
          setState(() {
            _changedHere = true;
            _tmpColorTemp = value.round();
          });
        },
        closing: Text("Warm", style: TextStyle(color: Colors.amberAccent),),
      );
    } else {
      return Container(width: 0.0, height: 0.0);
    }
  }

  Widget _buildColorControl(LightEntity entity) {
    if (entity.supportColor) {
      return LightColorPicker(
        color: _tmpColor,
        onColorSelected: (color) => _setColor(entity, color),
      );
    } else {
      return Container(width: 0.0, height: 0.0);
    }
  }

  void _showColorPicker(LightEntity entity) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          titlePadding: EdgeInsets.all(0.0),
          contentPadding: EdgeInsets.all(0.0),
          content: LightColorPicker(
            color: _tmpColor,
          ),
        );
      },
    );
  }

  Widget _buildEffectControl(LightEntity entity) {
    if ((entity.supportEffect) && (entity.effectList != null)) {
      return ModeSelectorWidget(
          onChange: (effect) => _setEffect(entity, effect),
          caption: "Effect",
          options: entity.effectList,
          value: _tmpEffect
      );
    } else {
      return Container(width: 0.0, height: 0.0);
    }
  }


}