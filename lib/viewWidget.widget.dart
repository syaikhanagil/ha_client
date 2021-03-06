part of 'main.dart';

class ViewWidget extends StatelessWidget {
  final HAView view;

  const ViewWidget({
    Key key,
    this.view
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget cardsContainer;
    Widget badgesContainer;
    if (this.view.isPanel) {
      cardsContainer = _buildPanelChild(context);
      badgesContainer = Container(width: 0, height: 0);
    } else {
      if (this.view.badges != null && this.view.badges is BadgesData) {
        badgesContainer = this.view.badges.buildCardWidget();
      } else {
        badgesContainer = Container(width: 0, height: 0);
      }
      if (this.view.cards.isNotEmpty) {
        cardsContainer = DynamicMultiColumnLayout(
          minColumnWidth: Sizes.minViewColumnWidth,
          children: this.view.cards.map((card) {
            if (card.conditions.isNotEmpty) {
              bool showCardByConditions = true;
              for (var condition in card.conditions) {
                Entity conditionEntity = HomeAssistant().entities.get(condition['entity']);
                if (conditionEntity != null &&
                    ((condition['state'] != null && conditionEntity.state != condition['state']) ||
                    (condition['state_not'] != null && conditionEntity.state == condition['state_not']))
                  ) {
                  showCardByConditions = false;
                  break;
                }
              }
              if (!showCardByConditions) {
                return Container(width: 0.0, height: 0.0,);
              }
            }
            return card.buildCardWidget();
          }).toList(),
        );
      } else {
        cardsContainer = Container();
      }
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          badgesContainer,
          cardsContainer
        ],
      ),
    );
  }

  Widget _buildPanelChild(BuildContext context) {
    if (this.view.cards != null && this.view.cards.isNotEmpty) {
      return this.view.cards[0].buildCardWidget();
    } else {
      return Container(width: 0, height: 0);
    }
  }

}