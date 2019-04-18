#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

int gValue = 0;
pthread_mutex_t gMtx;
pthread_mutexattr_t attrs;

/*

Como criar um mutex recursivo em pthreads:


- Aloque uma variável attrs do tipo pthread_mutexattr_t; 
- Inicialize attrs usando pthread_mutexattr_init(&attrs); 
- Sete o tipo do mutex para PTHREAD_MUTEX_RECURSIVE usando pthread_mutexattr_settype(); 
- Inicialize o mutex com os atributes em attrs usando pthread_mutex_init(); 
- Por fim, destrua attrs usando pthread_mutexattr_destroy().

*/

// Função imprime resultados na correção do exercício -- definida em helper.c
void imprimir_resultados(int n, int** results);

// Função escrita por um engenheiro
void compute(int arg) {
    if (arg < 2) {
        pthread_mutex_lock(&gMtx);
        gValue += arg;
        pthread_mutex_unlock(&gMtx);
    } else {
        compute(arg - 1);
        compute(arg - 2);
    }
}

// Função wrapper que pode ser usada com pthread_create() para criar uma 
// thread que retorna o resultado de compute(arg
void* compute_thread(void* arg) {
    int* ret = malloc(sizeof(int));
    pthread_mutex_lock(attrs);
    gValue = 0;
    compute(*((int*)arg));
    *ret = gValue;
    pthread_mutex_unlock(attrs);
    return ret;
}


int main(int argc, char** argv) {


    // Temos n_threads?
    if (argc < 2) {
        printf("Uso: %s n_threads x1 x2 ... xn\n", argv[0]);
        return 1;
    }
    // n_threads > 0 e foi dado um x para cada thread?
    int n_threads = atoi(argv[1]);
    if (!n_threads || argc < 2+n_threads) {
        printf("Uso: %s n_threads x1 x2 ... xn\n", argv[0]);
        return 1;
    }

    //Inicializa o mutex
    
    pthread_mutexattr_init(&attrs);
    pthread_mutexattr_settype(PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(attrs);



    //pthread_mutex_init(&gMtx);

    int args[n_threads];
    int* results[n_threads];
    pthread_t threads[n_threads];
    //Cria threads repassando argv[] correspondente
    for (int i = 0; i < n_threads; ++i)  {
        args[i] = atoi(argv[2+i]);
        pthread_create(&threads[i], NULL, compute_thread, &args[i]);
    }
    // Faz join em todas as threads e salva resultados
    for (int i = 0; i < n_threads; ++i)
        pthread_join(threads[i], (void**)&results[i]);

    // Não usaremos mais o mutex
    //pthread_mutex_destroy(&gMtx);
    pthread_mutex_destroy(&attrs);

    // Imprime resultados na tela
    // Importante: deve ser chamada para que a correção funcione
    imprimir_resultados(n_threads, results);

    // Faz o free para os resultados criados nas threads
    for (int i = 0; i < n_threads; ++i) 
        free(results[i]);
    
    return 0;
}
