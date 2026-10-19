import 'package:flutter/services.dart';

String _agruparMiles(String digitos) {
  if (digitos.isEmpty) return '';
  final buf = StringBuffer();
  final n = digitos.length;
  for (var i = 0; i < n; i++) {
    if (i > 0 && (n - i) % 3 == 0) buf.write('.');
    buf.write(digitos[i]);
  }
  return buf.toString();
}

/// Formatea un campo de texto como monto en pesos mientras se escribe:
/// separador de miles "." y decimales opcionales con ",", máximo 2 dígitos.
/// Bloquea cualquier caracter que no sea dígito o una coma (nada de letras).
/// Se usa junto al prefijo visual "$ " en la decoración del TextField (el
/// símbolo no forma parte del texto editable ni hay que sacarlo al parsear).
class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final buffer = StringBuffer();
    var vistaComa = false;
    for (final ch in newValue.text.split('')) {
      if (RegExp(r'[0-9]').hasMatch(ch)) {
        buffer.write(ch);
      } else if (ch == ',' && !vistaComa) {
        buffer.write(ch);
        vistaComa = true;
      }
    }
    final partes = buffer.toString().split(',');
    final entero = partes[0].replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final agrupado = _agruparMiles(entero);
    final decimales = partes.length > 1
        ? partes[1].substring(0, partes[1].length > 2 ? 2 : partes[1].length)
        : null;
    final texto = decimales == null ? agrupado : '$agrupado,$decimales';
    return TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));
  }
}

/// Parsea un texto formateado por [MoneyInputFormatter] a double. Saca
/// primero el separador de miles "." y recién después convierte la "," a
/// punto decimal — al revés se rompe (ej. "1.000,00" → "1.000.00" y
/// double.tryParse falla).
double parseMoney(String text) =>
    double.tryParse(text.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

/// Formatea un double al mismo estilo que ve el usuario mientras escribe
/// (separador de miles, coma decimal solo si hay centavos), para prellenar
/// el campo al editar un valor existente.
String fmtMoneyInput(double n) {
  final negativo = n < 0;
  final abs = n.abs();
  final entero = abs.truncate().toString();
  final agrupado = _agruparMiles(entero);
  final esEntero = abs == abs.truncate();
  final texto = esEntero
      ? agrupado
      : '$agrupado,${abs.toStringAsFixed(2).split('.').last}';
  return negativo ? '-$texto' : texto;
}
