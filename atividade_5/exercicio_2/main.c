#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>
#include <time.h>
#include <semaphore.h>

int produzir(int value);    //< definida em helper.c
void consumir(int produto); //< definida em helper.c
void *produtor_func(void *arg);
void *consumidor_func(void *arg);

sem_t sem_produzir,sem_consumir;
pthread_mutex_t mutex_produtor, mutex_consumidor;
int indice_produtor, indice_consumidor, tamanho_buffer;
int* buffer;

//Você deve fazer as alterações necessárias nesta função e na função
//consumidor_func para que usem semáforos para coordenar a produção
//e consumo de elementos do buffer.
void *produtor_func(void *arg) {
    //arg contem o número de itens a serem produzidos
    int max = *((int*)arg);
    for (int i = 0; i <= max; ++i) {
        int produto;
        if (i == max)
            produto = -1;          //envia produto sinlizando FIM
        else
            produto = produzir(i); //produz um elemento normal

        sem_wait(&sem_produzir);
        pthread_mutex_lock(&mutex_produtor);
        indice_produtor = (indice_produtor + 1) % tamanho_buffer; //calcula posição próximo elemento
        buffer[indice_produtor] = produto; //adiciona o elemento produzido à lista
        pthread_mutex_unlock(&mutex_produtor);
        sem_post(&sem_consumir);
    }
    return NULL;
}

void *consumidor_func(void *arg) {
    while (1) {
        sem_wait(&sem_consumir);
        pthread_mutex_lock(&mutex_consumidor);
        indice_consumidor = (indice_consumidor + 1) % tamanho_buffer; //Calcula o próximo item a consumir
        int produto = buffer[indice_consumidor]; //obtém o item da lista
        pthread_mutex_unlock(&mutex_consumidor);
        sem_post(&sem_produzir);

        //Podemos receber um produto normal ou um produto especial
        if (produto >= 0){
            consumir(produto); //Consome o item obtido.
        } else
            break; //produto < 0 é um sinal de que o consumidor deve parar
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc < 5) {
        printf("Uso: %s tamanho_buffer itens_produzidos n_produtores n_consumidores \n", argv[0]);
        return 0;
    }

    tamanho_buffer = atoi(argv[1]);
    int itens = atoi(argv[2]);
    int n_produtores = atoi(argv[3]);
    int n_consumidores = atoi(argv[4]);
    int consumidores_extras = n_consumidores - n_produtores;

    printf("itens=%d, n_produtores=%d, n_consumidores=%d\n",
	   itens, n_produtores, n_consumidores);

    //Iniciando buffer
    indice_produtor = 0;
    buffer = malloc(sizeof(int) * tamanho_buffer);
    indice_consumidor = 0;

    // Crie threads e o que mais for necessário para que n_produtores
    // threads criem cada uma n_itens produtos e o n_consumidores os
    // consumam.

    // ....
    pthread_mutex_init(&mutex_produtor, NULL); // Inicializa o mutex destravado
    pthread_mutex_init(&mutex_consumidor, NULL); // Inicializa o mutex destravado

    pthread_t threads_produtores[n_produtores];
    pthread_t threads_consumidores[n_consumidores];

    sem_init(&sem_produzir, 0, tamanho_buffer);
    sem_init(&sem_consumir, 0, 0);

    for (size_t i = 0; i < n_produtores; i++) {
      pthread_create(&threads_produtores[i], NULL, produtor_func, &itens);
    }

    for (size_t i = 0; i < n_consumidores; i++) {
      pthread_create(&threads_consumidores[i], NULL, consumidor_func, NULL);
    }

    for (size_t i = 0; i < n_produtores; i++) {
      pthread_join(threads_produtores[i], NULL);
    }

    if (consumidores_extras > 0) {
        for (int i = 0; i < consumidores_extras; i++) {
            sem_wait(&sem_produzir);
            indice_produtor = (indice_produtor+1) % tamanho_buffer; //Calcula o próximo item a consumir
            buffer[indice_produtor] = -1; //obtém o item da lista
            sem_post(&sem_consumir);
        }
    }

    for (size_t i = 0; i < n_produtores; i++) {
      pthread_join(threads_consumidores[i], NULL);
    }

    pthread_mutex_destroy(&mutex_produtor);
    pthread_mutex_destroy(&mutex_consumidor);

    sem_destroy(&sem_produzir);
    sem_destroy(&sem_consumir);

    //Libera memória do buffer
    free(buffer);

    return 0;
}
