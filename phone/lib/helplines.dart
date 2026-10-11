/// Offline helpline directory shown on the home screen.
/// Defaults are India's national numbers. Change this one list for another
/// country; nothing else in the app depends on it.
class Helpline {
  final String label;
  final String number;
  const Helpline(this.label, this.number);
}

const helplines = <Helpline>[
  Helpline('Emergency (police / fire / ambulance)', '112'),
  Helpline('Women helpline', '1091'),
  Helpline('Women helpline (domestic abuse)', '181'),
  Helpline('Child helpline (CHILDLINE)', '1098'),
];
