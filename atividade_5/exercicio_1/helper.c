#include <time.h>
#include <stdio.h>

//    +============================+
//    |                            |
// ~~~| NÃO MODIFIQUE ESSE ARQUIVO |~~~
//    |                            |
//    +============================+

//Produz um elemento
int produzir(int value) {
    struct timespec ts = {0, (value%50)*1000*1000};
    nanosleep(&ts, NULL);
    return value;
}

//Consome um elemento.
void consumir(int produto) {
    printf("Consumindo %d\n", produto);
    struct timespec ts = {0, (produto%50)*1000*1000};
    nanosleep(&ts, NULL);
}
