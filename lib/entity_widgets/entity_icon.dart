part of '../main.dart';

class EntityIcon extends StatelessWidget {

  final EdgeInsetsGeometry padding;
  final double iconSize;

  const EntityIcon({Key key, this.iconSize: Sizes.iconSize, this.padding: const EdgeInsets.fromLTRB(
      Sizes.leftWidgetPadding, 0.0, 12.0, 0.0)}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final entityModel = EntityModel.of(context);
    return GestureDetector(
      child: Padding(
        padding: padding,
        child: MaterialDesignIcons.createIconWidgetFromEntityData(
            entityModel.entityWrapper,
            iconSize,
            EntityColor.stateColor(entityModel.entityWrapper.entity.state)
        ),
      ),
      onTap: () {
        if (entityModel.handleTap) {
          switch (entityModel.entityWrapper.tapAction) {
            case EntityTapAction.moreInfo: {
              eventBus.fire(
                  new ShowEntityPageEvent(entityModel.entityWrapper.entity));
              break;
            }
            case EntityTapAction.toggle: {
              eventBus.fire(
                  ServiceCallEvent("homeassistant", "toggle", entityModel.entityWrapper.entity.entityId, null));
              break;
            }
          }

        }
      }

    );
  }
}