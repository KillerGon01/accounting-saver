import '../../application/chat/send_chat_message.dart';
import '../../application/payroll/parse_payroll.dart';
import '../../application/reports/explain_monthly_report.dart';
import '../../application/savings/create_savings_goal.dart';
import '../../application/savings/explain_savings_suggestions.dart';
import 'help_topic.dart';

/// Título y pasos de ayuda de una pantalla, en castellano, sacados de lo ya
/// documentado en `README.md` y `docs/`: capa de presentación pura, sin
/// ninguna capacidad nueva.
class HelpEntry {
  const HelpEntry({required this.title, required this.steps});

  final String title;
  final List<String> steps;
}

/// Contenido de ayuda de cada pantalla (ver [HelpTopic]). Los límites
/// numéricos que aparecen en los pasos se leen de las constantes del
/// código (`SendChatMessage.maxQuestionsPerSession`,
/// `ExplainMonthlyReport.maxCommentsPerSession`,
/// `ParsePayroll.maxReadsPerSession`, `CreateSavingsGoal.maxGoalsPerUser`,
/// `ExplainSavingsSuggestions.maxExplanationsPerSession`), nunca escritos a
/// mano, para que este texto no se desincronice si cambian.
final Map<HelpTopic, HelpEntry> helpContent = {
  HelpTopic.transactions: const HelpEntry(
    title: 'Movimientos',
    steps: [
      'Añade un movimiento con el botón "Nuevo", o descríbelo en una frase (entrada en lenguaje natural) y confirma la propuesta antes de guardar.',
      'Navega entre meses con las flechas y consulta el balance, los ingresos y los gastos de ese mes.',
      'Busca y filtra con el icono de filtro: texto, categoría, tipo de movimiento e importe mínimo/máximo.',
      'Carga datos de ejemplo para probar la app sin introducir movimientos a mano.',
      'Desde la barra superior también puedes abrir el resumen del mes, el chat y la lectura de nóminas (si la IA está activada), o "Más opciones" para el perfil y las metas de ahorro.',
    ],
  ),
  HelpTopic.chat: HelpEntry(
    title: 'Chat financiero',
    steps: [
      'Pregunta sobre tus propios movimientos: cuánto has gastado, en qué categoría gastas más, comparaciones entre meses, gastos recurrentes o qué movimientos tienes en un periodo.',
      'El chat es de solo lectura: nunca crea, edita ni borra ningún movimiento.',
      'Tienes un máximo de ${SendChatMessage.maxQuestionsPerSession} preguntas por sesión.',
    ],
  ),
  HelpTopic.payroll: HelpEntry(
    title: 'Leer nómina en PDF',
    steps: [
      'Solo disponible en la web, con la IA activada.',
      'Sube el PDF de una nómina: la IA extrae el periodo, el bruto, las deducciones y el líquido.',
      'Las cifras se comprueban siempre en código; solo se propone un ingreso (por el formulario de movimientos) si cuadran.',
      'Usa solo documentos ficticios, nunca una nómina real: el nivel gratuito de Gemini permite a Google usar el contenido enviado.',
      'Tienes un máximo de ${ParsePayroll.maxReadsPerSession} lecturas por sesión.',
    ],
  ),
  HelpTopic.profile: const HelpEntry(
    title: 'Perfil',
    steps: [
      'Consulta los datos de tu cuenta y un resumen de tu actividad: movimientos totales, por origen, e ingresos/gastos acumulados.',
      'Puedes eliminar completamente tu cuenta y tus datos, confirmando con tu correo.',
    ],
  ),
  HelpTopic.monthlyReport: HelpEntry(
    title: 'Resumen del mes',
    steps: [
      'Consulta ingresos, gastos, balance y el gasto por categoría con su gráfico.',
      'Compara con el mes anterior y consulta la previsión de fin de mes a partir de tus gastos recurrentes.',
      'Revisa los gastos inusuales del mes en curso (sin IA, solo del mes en curso).',
      'Si la IA está activada, puedes generar un comentario sobre este mismo resumen, hasta ${ExplainMonthlyReport.maxCommentsPerSession} veces por sesión.',
    ],
  ),
  HelpTopic.savingsGoals: HelpEntry(
    title: 'Metas de ahorro',
    steps: [
      'Crea una meta con nombre, importe objetivo, lo ya ahorrado y una fecha límite; el progreso se calcula automáticamente.',
      'Puedes tener como máximo ${CreateSavingsGoal.maxGoalsPerUser} metas a la vez.',
      'Para cada meta, consulta opciones de ahorro: dónde liberar dinero según tus gastos recurrentes, un recorte de categoría o un gasto puntual.',
      'Si la IA está activada, puedes pedir una redacción en prosa de esas mismas opciones, hasta ${ExplainSavingsSuggestions.maxExplanationsPerSession} veces por sesión; nunca sustituye a la lista.',
    ],
  ),
  HelpTopic.savingsGoalForm: const HelpEntry(
    title: 'Nueva o editar meta de ahorro',
    steps: [
      'Indica el nombre, el importe objetivo, lo ya ahorrado y una fecha límite.',
      'Guarda para crear la meta o para actualizarla si ya existía.',
    ],
  ),
  HelpTopic.transactionForm: const HelpEntry(
    title: 'Nuevo o editar movimiento',
    steps: [
      'Indica el importe, la fecha, el concepto y la categoría.',
      'Si el movimiento viene de una propuesta (lenguaje natural o nómina), revisa los datos antes de guardar: nada se guarda sin tu confirmación.',
    ],
  ),
};
