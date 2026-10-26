import java.io.{File, FileWriter, PrintWriter}
import java.time.LocalDate
import scala.io.{Source, StdIn}
import scala.util.Try

case class Operation(date: String, kind: String, category: String, amount: BigDecimal) {
  def toCsv: String = s"$date,$kind,$category,$amount"
  def signed: BigDecimal = if (kind == "income") amount else -amount
}

object Expenses {
  val Header = "date,type,category,amount"

  def load(file: File): List[Operation] =
    if (!file.exists) Nil
    else {
      val source = Source.fromFile(file, "UTF-8")
      try {
        source.getLines().drop(1).filter(_.trim.nonEmpty).flatMap { line =>
          line.split(",") match {
            case Array(d, k, c, a) => Try(Operation(d, k, c, BigDecimal(a))).toOption
            case _                 => None
          }
        }.toList
      } finally source.close()
    }

  def append(file: File, op: Operation): Unit = {
    val isNew = !file.exists
    val out = new PrintWriter(new FileWriter(file, true))
    try {
      if (isNew) out.println(Header)
      out.println(op.toCsv)
    } finally out.close()
  }

  def report(ops: List[Operation]): Unit = {
    val balance = ops.map(_.signed).sum
    println(f"Operations: ${ops.size}, balance: $balance%.2f")
    for (kind <- List("income", "expense")) {
      val byCategory = ops.filter(_.kind == kind).groupBy(_.category)
        .map { case (c, list) => c -> list.map(_.amount).sum }
        .toList.sortBy(-_._2)
      if (byCategory.nonEmpty) {
        println(s"  $kind:")
        for ((c, sum) <- byCategory) println(f"    $c%-12s $sum%10.2f")
      }
    }
  }

  def parse(line: String): Either[String, Operation] =
    line.trim.split("\\s+") match {
      case Array(kind, category, amount) =>
        if (kind != "income" && kind != "expense") Left(s"unknown type '$kind', use income or expense")
        else if (category.contains(",")) Left("category must not contain commas")
        else Try(BigDecimal(amount)).toOption.filter(_ > 0) match {
          case Some(a) => Right(Operation(LocalDate.now.toString, kind, category, a))
          case None    => Left(s"'$amount' is not a positive number")
        }
      case _ => Left("format: <income|expense> <category> <amount>")
    }

  def main(args: Array[String]): Unit = {
    val file = new File(if (args.nonEmpty) args(0) else "expenses.csv")
    var ops = load(file)
    println(s"History file: ${file.getPath}")
    report(ops)
    println("Enter: <income|expense> <category> <amount>, or 'report', or 'exit'")

    var running = true
    while (running) {
      print("> ")
      val line = StdIn.readLine()
      if (line == null || line.trim == "exit") running = false
      else if (line.trim == "report") report(ops)
      else if (line.trim.nonEmpty) parse(line) match {
        case Right(op) =>
          append(file, op)
          ops = ops :+ op
          println(s"Saved: ${op.toCsv}")
        case Left(error) => println(s"Error: $error")
      }
    }
    println("Bye!")
  }
}
