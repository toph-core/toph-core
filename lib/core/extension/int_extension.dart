

import 'package:flutter/material.dart';

extension IntExtension on int{
 
  Widget get wBox => SizedBox(width: this.toDouble());

  Widget get hBox => SizedBox(height: this.toDouble());


}
